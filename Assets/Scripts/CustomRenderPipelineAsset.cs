using System.Collections;
using UnityEngine;
using UnityEngine.Rendering;

[CreateAssetMenu(menuName = "Rendering/Custom Render Pipeline")]
public partial class CustomRenderPipelineAsset : RenderPipelineAsset
{
    
    [SerializeField]
	CameraBufferSettings cameraBuffer = new CameraBufferSettings { //摄像机缓冲区设置
		allowHDR = true,  //是否开启高动态范围颜色
        renderScale = 1f, //摄像机缓冲区缩放
		fxaa = new CameraBufferSettings.FXAA { //快速近似抗锯齿参数
			fixedThreshold = 0.0833f,
			relativeThreshold = 0.166f,
			subpixelBlending = 0.75f
		}
	};
    [SerializeField]
    bool useDynamicBatching = true; //是否开启动态合批
    [SerializeField]
    bool useGPUInstancing = true; //是否开启GPU实例化
    [SerializeField]
    bool useSRPBatcher = true; //是否开启可编程渲染管线合批
    [SerializeField]
    bool useLightsPerObject = true; //是否开启每个对象光照

    [SerializeField]
    ShadowSettings shadowSettings = default; //阴影设置
    [SerializeField]
	PostFXSettings postFXSettings = default; //后处理设置

    public enum ColorLUTResolution { _16 = 16, _32 = 32, _64 = 64 } 
	[SerializeField]
	ColorLUTResolution colorLUTResolution = ColorLUTResolution._32; //颜色查表法分辨率
    [SerializeField]
	Shader cameraRendererShader = default; //摄像机渲染着色器（包含：复制摄像机颜色缓冲区、深度缓冲区通道）

    protected override RenderPipeline CreatePipeline()
    {
        return new CustomRenderPipeline(cameraBuffer, useDynamicBatching, useGPUInstancing, useSRPBatcher, useLightsPerObject, shadowSettings, postFXSettings, (int)colorLUTResolution,
			cameraRendererShader);
    }
}
