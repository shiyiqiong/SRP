using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public partial class CameraRender
{
    ScriptableRenderContext context;
    Camera camera;
    const string bufferName = "Render Camera";
    CommandBuffer buffer = new CommandBuffer {
        name = bufferName
    };
    CullingResults cullingResults;
    static ShaderTagId unlitShaderTagId = new ShaderTagId("SRPDefaultUnlit");
    static ShaderTagId litShaderTagId = new ShaderTagId("CustomLit");
    static int bufferSizeId  = Shader.PropertyToID("_CameraBufferSize");
    static int colorAttachmentId  = Shader.PropertyToID("_CameraColorAttachment");
    static int depthAttachmentId  = Shader.PropertyToID("_CameraDepthAttachment");
    static int colorTextureId  = Shader.PropertyToID("_CameraColorTexture");
    static int depthTextureId  = Shader.PropertyToID("_CameraDepthTexture");
    static int sourceTextureId  = Shader.PropertyToID("_SourceTexture");
    static int srcBlendId  = Shader.PropertyToID("_CameraSrcBlend");
    static int dstBlendId   = Shader.PropertyToID("_CameraDstBlend");

    static CameraSettings defaultCameraSettings = new CameraSettings();

    static bool copyTextureSupported = SystemInfo.copyTextureSupport > CopyTextureSupport.None; //判断是否支持纹理

    Lighting lighting = new Lighting();

    PostFXStack postFXStack = new PostFXStack();

    bool useHDR, useScaledRendering;

    bool useColorTexture;
    bool useDepthTexture;
    bool useIntermediateBuffer;

    Material material;

    Texture2D missingTexture;

    static Rect fullViewRect = new Rect(0f, 0f, 1f, 1f);

    Vector2Int bufferSize;

    public const float renderScaleMin = 0.1f, renderScaleMax = 2f;

    public CameraRender (Shader shader) {
		material = CoreUtils.CreateEngineMaterial(shader); //通过shader创建一个材质
        missingTexture = new Texture2D(1, 1) {
			hideFlags = HideFlags.HideAndDontSave,
			name = "Missing"
		};
		missingTexture.SetPixel(0, 0, Color.white * 0.5f);
		missingTexture.Apply(true, true);
	}

    public void Render(ScriptableRenderContext context, Camera camera, CameraBufferSettings bufferSettings, bool useDynamicBatching, bool useGPUInstancing, bool useLightsPerObject, ShadowSettings shadowSettings, PostFXSettings postFXSettings,
		int colorLUTResolution)
    {
        this.context = context;
        this.camera = camera;

        var crpCamera = camera.GetComponent<CustomRenderPipelineCamera>();
		CameraSettings cameraSettings = crpCamera ? crpCamera.Settings : defaultCameraSettings;

        if(camera.cameraType == CameraType.Reflection) //判断是否为渲染反射探针摄像机
        {
            useColorTexture = bufferSettings.copyColorReflection;
			useDepthTexture = bufferSettings.copyDepthReflection;
		}
		else
        {
            useColorTexture = bufferSettings.copyColor && cameraSettings.copyColor;
			useDepthTexture = bufferSettings.copyDepth && cameraSettings.copyDepth;
		}

        if(cameraSettings.overridePostFX) 
        {
            postFXSettings = cameraSettings.postFXSettings;
        }

        float renderScale = cameraSettings.GetRenderScale(bufferSettings.renderScale);
		useScaledRendering = renderScale < 0.99f || renderScale > 1.01f;

        PrepareBuffer();
        PrepareForSceneWindow();
        //1.裁剪
        if(!Cull(shadowSettings.maxDistance))
        {
            return;
        }

        useHDR = bufferSettings.allowHDR && camera.allowHDR;
        if (useScaledRendering)
        {
            renderScale = Mathf.Clamp(renderScale, renderScaleMin, renderScaleMax);
			bufferSize.x = (int)(camera.pixelWidth * renderScale);
			bufferSize.y = (int)(camera.pixelHeight * renderScale);
		}
		else
        {
			bufferSize.x = camera.pixelWidth;
			bufferSize.y = camera.pixelHeight;
		}

        buffer.BeginSample(SampleName);
        buffer.SetGlobalVector(bufferSizeId, new Vector4(1f / bufferSize.x, 1f / bufferSize.y, bufferSize.x, bufferSize.y));
        ExecuteBuffer();
        //2.设置
        lighting.Setup(context, cullingResults, shadowSettings, useLightsPerObject, cameraSettings.maskLights ? cameraSettings.renderingLayerMask : -1);
        bufferSettings.fxaa.enabled &= cameraSettings.allowFXAA;
        postFXStack.Setup(context, camera, bufferSize, postFXSettings, cameraSettings.keepAlpha, useHDR, colorLUTResolution, cameraSettings.finalBlendMode, bufferSettings.bicubicRescaling,
			bufferSettings.fxaa);
        buffer.EndSample(SampleName);
        Setup();
        //3.渲染
        DrawVisibleGeometry(useDynamicBatching, useGPUInstancing, useLightsPerObject, cameraSettings.renderingLayerMask); //绘制可见几何图形
        DrawUnsupportedShaders(); //绘制不支持着色器
        DrawGizmosBeforeFX(); //绘制可视化辅助（Gizmos）
        //4.渲染后处理效果
        if(postFXStack.IsActive)
        {
			postFXStack.Render(colorAttachmentId); 
		}
        else if (useIntermediateBuffer) //没有启用后处理，但使用了中间缓冲区，需要将渲染到目标摄像机
        {
			DrawFinal(cameraSettings.finalBlendMode);
			ExecuteBuffer();
		}
        DrawGizmosAfterFX();//绘制可视化辅助（Gizmos）
        //5.清理
		Cleanup();
        //6.发送
        Submit();
    }

    bool Cull(float maxShadowDistance)
    {
        if(camera.TryGetCullingParameters(out ScriptableCullingParameters p)){
            p.shadowDistance = Mathf.Min(maxShadowDistance, camera.farClipPlane);
            cullingResults = context.Cull(ref p);
            return true;
        }
        return false;
    }

    void Setup()
    {
        context.SetupCameraProperties(camera);
        CameraClearFlags flags = camera.clearFlags;
        
        useIntermediateBuffer = useScaledRendering || useColorTexture || useDepthTexture || postFXStack.IsActive; //是否使用中间缓冲区（使用缩放渲染、使用颜色纹理、使用深度纹理，开启后处理）
        if(useIntermediateBuffer)
        {
            if (flags > CameraClearFlags.Color) { //当绘制中间缓冲区时，始终清除深度和颜色
				flags = CameraClearFlags.Color;
			}
            //创建一张临时颜色渲染贴图
			buffer.GetTemporaryRT(
				colorAttachmentId, bufferSize.x, bufferSize.y,
				0, FilterMode.Bilinear, useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default
			); 
            //创建一张临时深度渲染贴图
            buffer.GetTemporaryRT(
				depthAttachmentId, bufferSize.x, bufferSize.y,
				32, FilterMode.Point, RenderTextureFormat.Depth
			);
            //将渲染目标设置为临时的颜色、深度渲染贴图
			buffer.SetRenderTarget(
				colorAttachmentId,
				RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
				depthAttachmentId,
				RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store
			);
		}

        buffer.ClearRenderTarget(
            flags <= CameraClearFlags.Depth, 
            flags == CameraClearFlags.Color, 
            flags == CameraClearFlags.Color ? camera.backgroundColor.linear :Color.clear);
        buffer.BeginSample(SampleName);
        buffer.SetGlobalTexture(colorTextureId, missingTexture);
        buffer.SetGlobalTexture(depthTextureId, missingTexture);
        ExecuteBuffer();
        
    }

    //绘制可见几何体
    void DrawVisibleGeometry(bool useDynamicBatching, bool useGPUInstancing, bool useLightsPerObject, int renderingLayerMask)
    {
        PerObjectData lightsPerObjectFlags = useLightsPerObject ?
			PerObjectData.LightData | PerObjectData.LightIndices :
			PerObjectData.None; //设置是否启用每个对象的光照模式
        var sortingSettings = new SortingSettings(camera){
            criteria = SortingCriteria.CommonOpaque
        };
        var drawingSettings = new DrawingSettings(
            unlitShaderTagId, sortingSettings
        ){
            enableDynamicBatching = useDynamicBatching,
	        enableInstancing = useGPUInstancing,
            perObjectData = PerObjectData .ReflectionProbes | PerObjectData.Lightmaps |PerObjectData.ShadowMask | PerObjectData.LightProbe | PerObjectData.OcclusionProbe | PerObjectData.LightProbeProxyVolume |
				PerObjectData .OcclusionProbeProxyVolume | lightsPerObjectFlags
        };

        //1.绘制不透明几何体
        drawingSettings.SetShaderPassName(1, litShaderTagId);
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque, renderingLayerMask: (uint) renderingLayerMask); //设置过滤器：只渲染不透明物体和处于对应渲染层
        context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings); 
        //2.绘制天空盒
        context.DrawSkybox(camera); 
        //3.复制中间帧缓冲区（深度和颜色中间帧缓冲区，仅在渲染透明对象时可用）
        if (useColorTexture || useDepthTexture)
        {
			CopyAttachments(); 
		}
        //4.绘制透明几何体
        sortingSettings.criteria = SortingCriteria.CommonTransparent;
        drawingSettings.sortingSettings = sortingSettings;
        filteringSettings.renderQueueRange = RenderQueueRange.transparent;
        context.DrawRenderers(cullingResults, ref drawingSettings, ref filteringSettings); 
    }

    void Draw(RenderTargetIdentifier from, RenderTargetIdentifier to, bool isDepth = false)
    {
		buffer.SetGlobalTexture(sourceTextureId, from);
		buffer.SetRenderTarget(
			to, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store
		);
		buffer.DrawProcedural(
			Matrix4x4.identity, material, isDepth ? 1 : 0, MeshTopology.Triangles, 3
		);
	}

    //最终将中间缓冲区数据渲染到摄像机渲染缓冲区
    void DrawFinal (CameraSettings.FinalBlendMode finalBlendMode) {
		buffer.SetGlobalFloat(srcBlendId, (float)finalBlendMode.source);
		buffer.SetGlobalFloat(dstBlendId, (float)finalBlendMode.destination);
		buffer.SetGlobalTexture(sourceTextureId, colorAttachmentId);
		buffer.SetRenderTarget(
			BuiltinRenderTextureType.CameraTarget,
			finalBlendMode.destination == BlendMode.Zero && camera.rect == fullViewRect?
				RenderBufferLoadAction.DontCare : RenderBufferLoadAction.Load,
			RenderBufferStoreAction.Store
		);
		buffer.SetViewport(camera.pixelRect);
		buffer.DrawProcedural(
			Matrix4x4.identity, material, 0, MeshTopology.Triangles, 3
		);
		buffer.SetGlobalFloat(srcBlendId, 1f);
		buffer.SetGlobalFloat(dstBlendId, 0f);
	}

    void Submit()
    {
        buffer.EndSample(SampleName);
        ExecuteBuffer();
        context.Submit();
    }

    void ExecuteBuffer () 
    {
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }

    //复制中间帧缓冲区（因为中间帧缓冲区用于渲染，需要要采样时，需要再复制一张才能用于采样）
    void CopyAttachments()
    {
        if (useColorTexture) {
			buffer.GetTemporaryRT(
				colorTextureId, bufferSize.x, bufferSize.y,
				0, FilterMode.Bilinear, useHDR ?
					RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default
			);
			if (copyTextureSupported) //判断是否支持复制纹理
            {
				buffer.CopyTexture(colorAttachmentId, colorTextureId);
			}
			else {
				Draw(colorAttachmentId, colorTextureId);
			}
		}
		if (useDepthTexture) //判断是否使用深度纹理
        {
			buffer.GetTemporaryRT(
				depthTextureId, bufferSize.x, bufferSize.y,
				32, FilterMode.Point, RenderTextureFormat.Depth
			);
			if(copyTextureSupported) //判断是否支持复制纹理
            {
				buffer.CopyTexture(depthAttachmentId, depthTextureId); //复制一张深度纹理
			}
			else
            {
				Draw(depthAttachmentId, depthTextureId, true); //重新绘制一张深度纹理
			}
		}
        if (!copyTextureSupported) {
			buffer.SetRenderTarget(
				colorAttachmentId,
				RenderBufferLoadAction.Load, RenderBufferStoreAction.Store,
				depthAttachmentId,
				RenderBufferLoadAction.Load, RenderBufferStoreAction.Store
			);
		}
		ExecuteBuffer();
	}

    void Cleanup()
    {
		lighting.Cleanup();
		if (useIntermediateBuffer) { //判断是否使用了中间缓冲区
			buffer.ReleaseTemporaryRT(colorAttachmentId);
            buffer.ReleaseTemporaryRT(depthAttachmentId);
            if (useColorTexture) {
				buffer.ReleaseTemporaryRT(colorTextureId);
			}
            if (useDepthTexture) {
                buffer.ReleaseTemporaryRT(depthTextureId);
            }
        }
	}

    public void Dispose ()
    {
		CoreUtils.Destroy(material); //释放材质
        CoreUtils.Destroy(missingTexture); //释放纹理
	}
}
