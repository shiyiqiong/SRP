using UnityEngine;
using UnityEngine.Rendering;
using static PostFXSettings;

public partial class PostFXStack 
{
    const string bufferName = "Post FX";
    const int maxBloomPyramidLevels = 16;

    int bloomBucibicUpsamplingId = Shader.PropertyToID("_BloomBicubicUpsampling");
    int bloomPrefilterId = Shader.PropertyToID("_BloomPrefilter");
	int bloomResultId = Shader.PropertyToID("_BloomResult");
    int bloomThresholdId = Shader.PropertyToID("_BloomThreshold");
    int bloomIntensityId = Shader.PropertyToID("_BloomIntensity");
    int fxSourceId = Shader.PropertyToID("_PostFXSource");
    int fxSource2Id = Shader.PropertyToID("_PostFXSource2");
	int colorAdjustmentsId = Shader.PropertyToID("_ColorAdjustments");
	int colorFilterId = Shader.PropertyToID("_ColorFilter");
	int whiteBalanceId = Shader.PropertyToID("_WhiteBalance");
	int splitToningShadowsId = Shader.PropertyToID("_SplitToningShadows");
	int splitToningHighlightsId = Shader.PropertyToID("_SplitToningHighlights");
	int channelMixerRedId = Shader.PropertyToID("_ChannelMixerRed");
	int channelMixerGreenId = Shader.PropertyToID("_ChannelMixerGreen");
	int channelMixerBlueId = Shader.PropertyToID("_ChannelMixerBlue");
	
	int smhShadowsId = Shader.PropertyToID("_SMHShadows");
	int smhMidtonesId = Shader.PropertyToID("_SMHMidtones");
	int smhHighlightsId = Shader.PropertyToID("_SMHHighlights");
	int smhRangeId = Shader.PropertyToID("_SMHRange");

	int colorGradingLUTId = Shader.PropertyToID("_ColorGradingLUT");
	int colorGradingLUTParametersId = Shader.PropertyToID("_ColorGradingLUTParameters");
	int colorGradingLUTInLogId = Shader.PropertyToID("_ColorGradingLUTInLogC");

	int finalSrcBlendId = Shader.PropertyToID("_FinalSrcBlend");
	int finalDstBlendId = Shader.PropertyToID("_FinalDstBlend");

	int copyBicubicId = Shader.PropertyToID("_CopyBicubic");
	int colorGradingResultId  = Shader.PropertyToID("_ColorGradingResult");
	int finalResultId = Shader.PropertyToID("_FinalResult");
	int fxaaConfigId = Shader.PropertyToID("_FXAAConfig");

	const string fxaaQualityLowKeyword = "FXAA_QUALITY_LOW";
	const string fxaaQualityMediumKeyword = "FXAA_QUALITY_MEDIUM";

    int bloomPyramidId;
	CameraBufferSettings.BicubicRescalingMode bicubicRescaling;

	CommandBuffer buffer = new CommandBuffer {
		name = bufferName
	};

	ScriptableRenderContext context;
	
	Camera camera;

	PostFXSettings settings;

    public bool IsActive => settings != null;

	bool keepAlpha, useHDR;

    enum Pass {
        BloomAdd,
        BloomHorizontal,
        BloomPrefilter,
		BloomPrefilterFireflies,
		BloomScatter,
		BloomScatterFinal,
        BloomVertical,
		Copy,
		ColorGradingNone,
		ToneMappingACES,
		ToneMappingNeutral,
        ToneMappingReinhard,
		ApplyColorGrading,
		ApplyColorGradingWithLuma,
		FinalRescale,
		FXAA,
		FXAAWithLuma
	}
	int colorLUTResolution;

	static Rect fullViewRect = new Rect(0f, 0f, 1f, 1f);
	Vector2Int bufferSize;

	CameraSettings.FinalBlendMode finalBlendMode;

	CameraBufferSettings.FXAA fxaa;

    
    public PostFXStack()
    {
		//设置泛光临时贴图的id
	    bloomPyramidId = Shader.PropertyToID("_BloomPyramid0");
		for(int i = 1; i < maxBloomPyramidLevels*2; i++) //考虑到做横向和纵向高斯模糊，数量需要增加2倍
        {
			Shader.PropertyToID("_BloomPyramid" + i);
		}
	}

	public void Setup(ScriptableRenderContext context, Camera camera, Vector2Int bufferSize, PostFXSettings settings, bool keepAlpha, bool useHDR, int colorLUTResolution, CameraSettings.FinalBlendMode finalBlendMode, CameraBufferSettings.BicubicRescalingMode bicubicRescaling,
		CameraBufferSettings.FXAA fxaa)
    {
		this.fxaa = fxaa;
		this.bicubicRescaling = bicubicRescaling;
		this.bufferSize = bufferSize;
		this.finalBlendMode = finalBlendMode;
		this.context = context;
		this.camera = camera;
		this.settings = camera.cameraType <= CameraType.SceneView ? settings : null; //只有游戏运行时摄像机和编辑器场景窗口摄像机才执行后处理效果
		this.keepAlpha = keepAlpha;
		this.useHDR = useHDR;
		this.colorLUTResolution = colorLUTResolution;
        ApplySceneViewState(); //场景窗口状态发生变化时（当场景窗口禁用后处理效果时，不执行后处理）
	}

    public void Render(int sourceId)
    {
       if (DoBloom(sourceId)) {
			DoFinal(bloomResultId);
			buffer.ReleaseTemporaryRT(bloomResultId);
		}
		else {
			DoFinal(sourceId);
		}
		context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
	}

	//通过后处理材质shader指定的pass通道进行渲染，采样from并最终渲染至to上
    void Draw(RenderTargetIdentifier from, RenderTargetIdentifier to, Pass pass)
    {
		buffer.SetGlobalTexture(fxSourceId, from);
		buffer.SetRenderTarget(to, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
		buffer.DrawProcedural(
			Matrix4x4.identity, settings.Material, (int)pass,
			MeshTopology.Triangles, 3
		);
	}

	//最终将图像渲染到摄像机渲染缓冲区
	void DrawFinal(RenderTargetIdentifier from, Pass pass)
    {
		buffer.SetGlobalFloat(finalSrcBlendId, (float)finalBlendMode.source);
		buffer.SetGlobalFloat(finalDstBlendId, (float)finalBlendMode.destination);
		buffer.SetGlobalTexture(fxSourceId, from);
		buffer.SetRenderTarget(
			BuiltinRenderTextureType.CameraTarget,
			finalBlendMode.destination == BlendMode.Zero && camera.rect == fullViewRect ?
				RenderBufferLoadAction.DontCare : RenderBufferLoadAction.Load,
			RenderBufferStoreAction.Store
		);
		buffer.SetViewport(camera.pixelRect);
		buffer.DrawProcedural(
			Matrix4x4.identity, settings.Material, (int)pass,
			MeshTopology.Triangles, 3
		);
	}

	//执行泛光后处理效果
    bool DoBloom(int sourceId)
    {
        BloomSettings bloom = settings.Bloom;
		int width, height;
		if (bloom.ignoreRenderScale)
		{
			width = camera.pixelWidth / 2;
			height = camera.pixelHeight / 2;
		}
		else
		{
			width = bufferSize.x / 2;
			height = bufferSize.y / 2;
		}

        if (bloom.maxIterations == 0 || bloom.intensity <= 0f ||
			height < bloom.downscaleLimit * 2 || width < bloom.downscaleLimit * 2)
        {
			return false;
		}
		
		//1.设置基础参数
		buffer.BeginSample("Bloom");
        Vector4 threshold;
		threshold.x = Mathf.GammaToLinearSpace(bloom.threshold);
		threshold.y = threshold.x * bloom.thresholdKnee;
		threshold.z = 2f * threshold.y;
		threshold.w = 0.25f / (threshold.y + 0.00001f);
		threshold.y -= threshold.x;
		buffer.SetGlobalVector(bloomThresholdId, threshold);
		RenderTextureFormat format = useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default; //判断是否淡化萤火虫效果

		//2.渲染一张临时渲染纹理，用于后续采样（考虑阈值对泛光影响，或考虑淡化萤光虫效果）
        buffer.GetTemporaryRT(
			bloomPrefilterId, width, height, 0, FilterMode.Bilinear, format
		);
		Draw(sourceId, bloomPrefilterId, bloom.fadeFireflies ? Pass.BloomPrefilterFireflies : Pass.BloomPrefilter); //减半分辨率纹理（判断是否淡化萤火虫效果）
		
		//3.渲染一批临时渲染纹理，用于后续泛光效果计算（逐步缩小分辨率，并进行高斯模糊的）
		width /= 2; //减半分辨率
		height /= 2; //减半分辨率
		int fromId = bloomPrefilterId, toId = bloomPyramidId + 1;
        int i;
		for (i = 0; i < bloom.maxIterations; i++)
        {
			if(height < bloom.downscaleLimit || width < bloom.downscaleLimit)
            {
				break;
			}
            int midId = toId - 1;
			buffer.GetTemporaryRT(midId, width, height, 0, FilterMode.Bilinear, format);
			buffer.GetTemporaryRT(toId, width, height, 0, FilterMode.Bilinear, format);
			Draw(fromId, midId, Pass.BloomHorizontal);
			Draw(midId, toId, Pass.BloomVertical);
			fromId = toId;
			toId += 2;
			width /= 2;
			height /= 2;
		}

		//4.选择叠加或散射模式，渲染泛光效果
        buffer.ReleaseTemporaryRT(bloomPrefilterId);
        buffer.SetGlobalFloat(bloomBucibicUpsamplingId, bloom.bicubicUpsampling ? 1f : 0f);
        buffer.SetGlobalFloat(bloomIntensityId, 1f);
		Pass combinePass, finalPass;
		float finalIntensity;
		if (bloom.mode == BloomSettings.Mode.Additive) //叠加泛光
		{ 
			combinePass = finalPass = Pass.BloomAdd;
			buffer.SetGlobalFloat(bloomIntensityId, 1f); //设置每一级泛光强度
			finalIntensity = bloom.intensity; //设置最终泛光强
		}
		else //散射泛光
		{
			combinePass = Pass.BloomScatter;
			finalPass = Pass.BloomScatterFinal;
			buffer.SetGlobalFloat(bloomIntensityId, bloom.scatter); //设置每一级泛光强度
			finalIntensity = Mathf.Min(bloom.intensity, 0.95f); //设置最终泛光强度
		}
        if(i > 1)
        {
            buffer.ReleaseTemporaryRT(fromId - 1); //释放倒数第一迭代水平绘制的纹理
            toId -= 5; //将目标设置为倒数第二迭代水平绘制纹理
            for (i -= 1; i > 0; i--)
            {
                buffer.SetGlobalTexture(fxSource2Id, toId + 1);
                Draw(fromId, toId, combinePass);
                buffer.ReleaseTemporaryRT(fromId);
                buffer.ReleaseTemporaryRT(toId + 1);
                fromId = toId;
                toId -= 2;
            }
        }
        else
        {
            buffer.ReleaseTemporaryRT(bloomPyramidId);
        }

		//5.将泛光效果渲染到最终泛光结果临时纹理上
        buffer.SetGlobalFloat(bloomIntensityId, finalIntensity);
        buffer.SetGlobalTexture(fxSource2Id, sourceId);
		buffer.GetTemporaryRT(
			bloomResultId, bufferSize.x, bufferSize.y, 0,
			FilterMode.Bilinear, format
		);
		Draw(fromId, bloomResultId, finalPass);
		buffer.ReleaseTemporaryRT(fromId);
		buffer.EndSample("Bloom");
		return true;
	}

	//颜色调整（包括：曝光，对比度，颜色过滤，色调偏移，饱和度）
	void ConfigureColorAdjustments () 
	{
		ColorAdjustmentsSettings colorAdjustments = settings.ColorAdjustments;
		buffer.SetGlobalVector(colorAdjustmentsId, new Vector4(
			Mathf.Pow(2f, colorAdjustments.postExposure), //曝光（缩放量为，2的多少次方）
			colorAdjustments.contrast * 0.01f + 1f, //对比度（范围转为[0, 2]）
			colorAdjustments.hueShift * (1f / 360f), //色调偏移（范围转为[-0.5, 0.5]）
			colorAdjustments.saturation * 0.01f + 1f //饱和度（范围转为[0, 2]）
		));
		buffer.SetGlobalColor(colorFilterId, colorAdjustments.colorFilter.linear); 
	}

	//白平衡（调节：色温，补偿绿色或洋红色）
	void ConfigureWhiteBalance ()
	{
		WhiteBalanceSettings whiteBalance = settings.WhiteBalance;
		buffer.SetGlobalVector(whiteBalanceId, ColorUtils.ColorBalanceToLMSCoeffs(
			whiteBalance.temperature, whiteBalance.tint
		)); //ColorBalanceToLMSCoeffs：将白平衡参数转换为LMS系数
	}

	//拆分着色（调节：阴影着色颜色，高光着色颜色，平衡值）
	void ConfigureSplitToning () 
	{
		SplitToningSettings splitToning = settings.SplitToning;
		Color splitColor = splitToning.shadows;
		splitColor.a = splitToning.balance * 0.01f;
		buffer.SetGlobalColor(splitToningShadowsId, splitColor);
		buffer.SetGlobalColor(splitToningHighlightsId, splitToning.highlights);
	}

	//通道混合器（设置红色、绿色、蓝色通道对其他通道影响）
	void ConfigureChannelMixer ()
	{
		ChannelMixerSettings channelMixer = settings.ChannelMixer;
		buffer.SetGlobalVector(channelMixerRedId, channelMixer.red);
		buffer.SetGlobalVector(channelMixerGreenId, channelMixer.green);
		buffer.SetGlobalVector(channelMixerBlueId, channelMixer.blue);
	}

	//阴影、中间调、高光（阴影偏移颜色，中间调偏移颜色，高光偏移颜色，阴影和中间调过渡起点，阴影和中间调过渡终点，中间调和高光过渡起点，中间调和高光过渡终点）
	void ConfigureShadowsMidtonesHighlights ()
	{
		ShadowsMidtonesHighlightsSettings smh = settings.ShadowsMidtonesHighlights;
		buffer.SetGlobalColor(smhShadowsId, smh.shadows.linear);
		buffer.SetGlobalColor(smhMidtonesId, smh.midtones.linear);
		buffer.SetGlobalColor(smhHighlightsId, smh.highlights.linear);
		buffer.SetGlobalVector(smhRangeId, new Vector4(
			smh.shadowsStart, smh.shadowsEnd, smh.highlightsStart, smh.highLightsEnd
		));
	}

	//设置快速近似抗锯齿数据
	void ConfigureFXAA () {
		if (fxaa.quality == CameraBufferSettings.FXAA.Quality.Low) { //低质量
			buffer.EnableShaderKeyword(fxaaQualityLowKeyword);
			buffer.DisableShaderKeyword(fxaaQualityMediumKeyword);
		}
		else if (fxaa.quality == CameraBufferSettings.FXAA.Quality.Medium) { //中质量
			buffer.DisableShaderKeyword(fxaaQualityLowKeyword);
			buffer.EnableShaderKeyword(fxaaQualityMediumKeyword);
		}
		else { //高质量
			buffer.DisableShaderKeyword(fxaaQualityLowKeyword); 
			buffer.DisableShaderKeyword(fxaaQualityMediumKeyword);
		}
		buffer.SetGlobalVector(fxaaConfigId, new Vector4(
			fxaa.fixedThreshold, fxaa.relativeThreshold, fxaa.subpixelBlending
		)); //固定阈值、相对阈值、亚像素混合
	}

	//执行最终后处理效果
	void DoFinal (int sourceId)
	{
		//1.设置颜色分级配置
		ConfigureColorAdjustments();
		ConfigureWhiteBalance();
		ConfigureSplitToning();
		ConfigureChannelMixer();
		ConfigureShadowsMidtonesHighlights();

		//2.创建查表临时渲染纹理
		int lutHeight = colorLUTResolution;
		int lutWidth = lutHeight * lutHeight;
		buffer.GetTemporaryRT(
			colorGradingLUTId, lutWidth, lutHeight, 0,
			FilterMode.Bilinear, RenderTextureFormat.DefaultHDR
		); 

		//3.把RGB三个通道颜色都执行颜色分级和色调映射，然后填充到查表纹理（获得查表所有输入颜色，执行颜色分级，渲染到临时纹理）
		buffer.SetGlobalVector(colorGradingLUTParametersId, new Vector4(
			lutHeight, 0.5f / lutWidth, 0.5f / lutHeight, lutHeight / (lutHeight - 1f)
		));
		ToneMappingSettings.Mode mode = settings.ToneMapping.mode;
		Pass pass = Pass.ColorGradingNone  + (int)mode;  //设置色调映射模式（None：不做色调映射；ACES：；Neutral：；Reinhard：）
		buffer.SetGlobalFloat(colorGradingLUTInLogId, useHDR && pass != Pass.ColorGradingNone ? 1f : 0f);
		Draw(sourceId, colorGradingLUTId, pass);

		//4.从要渲染的图像中获取颜色，通过查表纹理获得对应转换后的颜色，最后渲染到摄像机缓冲区中
		buffer.SetGlobalVector(colorGradingLUTParametersId,
			new Vector4(1f / lutWidth, 1f / lutHeight, lutHeight - 1f)
		);

		buffer.SetGlobalFloat(finalSrcBlendId, 1f);
		buffer.SetGlobalFloat(finalDstBlendId, 0f);
		if (fxaa.enabled) //如果开启fxaa，先执行颜色分级，将结果渲染到临时LDR纹理中
		{
			ConfigureFXAA();
			buffer.GetTemporaryRT(colorGradingResultId, bufferSize.x, bufferSize.y, 0,
				FilterMode.Bilinear, RenderTextureFormat.Default);
			Draw(sourceId, colorGradingResultId, keepAlpha ? Pass.ApplyColorGrading : Pass.ApplyColorGradingWithLuma);
		}

		if (bufferSize.x == camera.pixelWidth) 
		{
			if (fxaa.enabled)
			{
				DrawFinal(colorGradingResultId, keepAlpha ? Pass.FXAA : Pass.FXAAWithLuma); //如果没有渲染缩放，直接将颜色分级结果通过FXAA通道渲染到摄像机缓冲区
				buffer.ReleaseTemporaryRT(colorGradingResultId);
			}
			else
			{
				DrawFinal(sourceId, Pass.ApplyColorGrading); //如果没有渲染缩放，直接应用颜色分级渲染到摄像机缓冲区
			}
		}
		else 
		{
			
			buffer.GetTemporaryRT(finalResultId, bufferSize.x, bufferSize.y, 0,
				FilterMode.Bilinear, RenderTextureFormat.Default);
			if (fxaa.enabled)
			{
				Draw(colorGradingResultId, finalResultId, keepAlpha ? Pass.FXAA : Pass.FXAAWithLuma); //如果有渲染缩放，先将颜色分级结果通过FXAA通道渲染到临时渲染纹理
				buffer.ReleaseTemporaryRT(colorGradingResultId);
			}
			else
			{
				Draw(sourceId, finalResultId, Pass.ApplyColorGrading);  //如果有渲染缩放，先应用颜色分级渲染到临时渲染纹理（色调映射为LDR）
			}
			bool bicubicSampling =
				bicubicRescaling == CameraBufferSettings.BicubicRescalingMode.UpAndDown ||
				bicubicRescaling == CameraBufferSettings.BicubicRescalingMode.UpOnly &&
				bufferSize.x < camera.pixelWidth;

			buffer.SetGlobalFloat(copyBicubicId, bicubicSampling ? 1f : 0f);
			DrawFinal(finalResultId, Pass.FinalRescale); //最后在将临时纹理渲染（LDR）到摄像机缓冲区
			buffer.ReleaseTemporaryRT(finalResultId);
		}
		buffer.ReleaseTemporaryRT(colorGradingLUTId);
	}

}
