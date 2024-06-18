#ifndef CUSTOM_POST_FX_PASSES_INCLUDED
#define CUSTOM_POST_FX_PASSES_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"



//-----------------------------基础属性----------------------------------

TEXTURE2D(_PostFXSource);
TEXTURE2D(_PostFXSource2);
TEXTURE2D(_ColorGradingLUT);

float4 _PostFXSource_TexelSize; //纹理_PostFXSource的像素大小

float4 _ColorAdjustments;
float4 _ColorFilter;
float4 _WhiteBalance;
float4 _SplitToningShadows, _SplitToningHighlights;
float4 _ChannelMixerRed, _ChannelMixerGreen, _ChannelMixerBlue;
float4 _SMHShadows, _SMHMidtones, _SMHHighlights, _SMHRange;

float4 _BloomThreshold;
bool _BloomBicubicUpsampling;
float _BloomIntensity;

float4 _ColorGradingLUTParameters;
bool _ColorGradingLUTInLogC;
bool _CopyBicubic;



//-----------------------------基础函数----------------------------------

//返回_PostFXSource尺寸：x = 1/width；y = 1/height；z = width； w = height 
float4 GetSourceTexelSize() 
{
	return _PostFXSource_TexelSize;
}

//双线性插值采样_PostFXSource
float4 GetSource(float2 screenUV)
{
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource, sampler_linear_clamp, screenUV, 0);
}

//双线性插值采样_PostFXSource2
float4 GetSource2(float2 screenUV)
{
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource2, sampler_linear_clamp, screenUV, 0);
}

//双三次插值采样_PostFXSource
float4 GetSourceBicubic (float2 screenUV)
{
	return SampleTexture2DBicubic(
		TEXTURE2D_ARGS(_PostFXSource, sampler_linear_clamp), screenUV,
		_PostFXSource_TexelSize.zwxy, 1.0, 0.0
	);
}

float Luminance (float3 color, bool useACES)
{
	return useACES ? AcesLuminance(color) : Luminance(color);
}



//-----------------------------泛光相关函数----------------------------------

//泛光阈值
float3 ApplyBloomThreshold (float3 color)
{
	float brightness = Max3(color.r, color.g, color.b);
	float soft = brightness + _BloomThreshold.y;
	soft = clamp(soft, 0.0, _BloomThreshold.z);
	soft = soft * soft * _BloomThreshold.w;
	float contribution = max(soft, brightness - _BloomThreshold.x);
	contribution /= max(brightness, 0.00001);
	return color * contribution;
}


//-----------------------------颜色分级相关函数----------------------------------

//曝光
float3 ColorGradePostExposure (float3 color)
{
	return color * _ColorAdjustments.x; //按一定比例缩放颜色通道
}

//对比度
float3 ColorGradingContrast (float3 color, bool useACES)
{
	color = useACES ? ACES_to_ACEScc(unity_to_ACES(color)) : LinearToLogC(color); //LinearToLogC：线性颜色空间转对数颜色空间，unity_to_ACES：转换为ACES空间，ACES_to_ACEScc：转换为ACES对数空间
	color = (color - ACEScc_MIDGRAY) * _ColorAdjustments.y + ACEScc_MIDGRAY;  //将颜色减去中间灰度值（常量0.4135884），然后按对比度进行缩放，最后添加回中间灰度值
	return useACES ? ACES_to_ACEScg(ACEScc_to_ACES(color)) : LogCToLinear(color); //LogCToLinear：对数颜色空间转线性颜色空间，ACEScc_to_ACES：转换为ACES空间，ACES_to_ACEScg：转换为ACES线性框架
}

//颜色过滤器
float3 ColorGradeColorFilter (float3 color)
{
	return color * _ColorFilter.rgb; //分别对RGB三个颜色进行缩放
}

//色调偏移
float3 ColorGradingHueShift (float3 color)
{
	color = RgbToHsv(color); //将RGB颜色模型转换为HSV颜色模型（H：色调；S：饱和度；V：亮度）
	float hue = color.x + _ColorAdjustments.z; //添加色调偏移
	color.x = RotateHue(hue, 0.0, 1.0); //现在色调在[0, 1]范围，
	return HsvToRgb(color); //从HSV颜色模型转换为RGB颜色模型
}

//饱和度
float3 ColorGradingSaturation (float3 color, bool useACES)
{
	float luminance = Luminance(color, useACES);
	return (color - luminance) * _ColorAdjustments.w + luminance; //将颜色减去亮度值，然后按饱和度缩放， 最后添加回亮度
}

//白平衡
float3 ColorGradeWhiteBalance (float3 color)
{
	color = LinearToLMS(color); //颜色从线性空间转换到LMS空间
	color *= _WhiteBalance.rgb; //颜色乘于白平衡LMS系数
	return LMSToLinear(color); //颜色从LMS空间转换到线性空间
}

//拆分着色
float3 ColorGradeSplitToning (float3 color, bool useACES)
{
	color = LinearToGamma22(color); //线性颜色空间转伽马颜色空间
	float t = saturate(Luminance(saturate(color), useACES) + _SplitToningShadows.w); //平衡值为：亮度+平衡参数
	float3 shadows = lerp(0.5, _SplitToningShadows.rgb, 1.0 - t); //计算阴影颜色影响
	float3 highlights = lerp(0.5, _SplitToningHighlights.rgb, t); //计算高光颜色影响
	color = SoftLight(color, shadows); //将颜色和阴影颜色柔光混合
	color = SoftLight(color, highlights); //将颜色和高光颜色柔光混合
	return Gamma22ToLinear(color); //伽马颜色空间转线性颜色空间
}

//通道混合器
float3 ColorGradingChannelMixer (float3 color)
{
	return mul(
		float3x3(_ChannelMixerRed.rgb, _ChannelMixerGreen.rgb, _ChannelMixerBlue.rgb),
		color
	);  //对输入颜色进行通道混合，然后在输出颜色
}

//阴影、中间调、高光
float3 ColorGradingShadowsMidtonesHighlights (float3 color, bool useACES)
{
	float luminance = Luminance(color, useACES);
	//平滑阶梯函数 smoothstep(edge_low, edge_up, x)：将edge_low和edge_up映射到[0, 1]，再到x在[0, 1]的映射值（使用曲线来平滑结果）
	float shadowsWeight = 1.0 - smoothstep(_SMHRange.x, _SMHRange.y, luminance); //阴影权重
	float highlightsWeight = smoothstep(_SMHRange.z, _SMHRange.w, luminance); //高光权重
	float midtonesWeight = 1.0 - shadowsWeight - highlightsWeight; //中间调权重
	return
		color * _SMHShadows.rgb * shadowsWeight +
		color * _SMHMidtones.rgb * midtonesWeight +
		color * _SMHHighlights.rgb * highlightsWeight;
}

//颜色分级
float3 ColorGrade(float3 color, bool useACES = false)
{
	color = ColorGradePostExposure(color); //曝光
	color = ColorGradeWhiteBalance(color); //白平衡
	color = ColorGradingContrast(color, useACES); //对比度
	color = ColorGradeColorFilter(color); //颜色过滤器
	color = max(color, 0.0);
	color = ColorGradeSplitToning(color, useACES); //拆分着色
	color = ColorGradingChannelMixer(color); //通道混合器
	color = max(color, 0.0);
	color = ColorGradingShadowsMidtonesHighlights(color, useACES); //阴影、中间色调、高光
	color = ColorGradingHueShift(color); //色调偏移
	color = ColorGradingSaturation(color, useACES); //饱和度
	return max(useACES ? ACEScg_to_ACES(color) : color, 0.0);  //ACEScg_to_ACES：将颜色从ACES线性空间转换为ACES空间
}

//获得颜色分级查表颜色
float3 GetColorGradedLUT (float2 uv, bool useACES = false) {
	float3 color = GetLutStripValue(uv, _ColorGradingLUTParameters); //将UV转换为RGB颜色
	return ColorGrade(_ColorGradingLUTInLogC ? LogCToLinear(color) : color, useACES); //ColorGrade：执行颜色分级；LogCToLinear：扩展颜色范围，支持HDR
}

//应用颜色分级查表
float3 ApplyColorGradingLUT (float3 color)
{
	//根据输入颜色，重查表纹理中采用，再输出最终颜色
	return ApplyLut2D(
		TEXTURE2D_ARGS(_ColorGradingLUT, sampler_linear_clamp),
		saturate(_ColorGradingLUTInLogC ? LinearToLogC(color) : color),
		_ColorGradingLUTParameters.xyz
	);
}


//-----------------------------顶点着色器----------------------------------

struct Varyings {
	float4 positionCS : SV_POSITION;
	float2 screenUV : VAR_SCREEN_UV;
};

Varyings DefaultPassVertex (uint vertexID : SV_VertexID)
{
	Varyings output;
	//三角形面当中矩形X范围[-1, 1], y范围[-1, 1]
	output.positionCS = float4(
		vertexID <= 1 ? -1.0 : 3.0,
		vertexID == 1 ? 3.0 : -1.0,
		0.0, 1.0
	);
	//三角形面当中矩形屏幕UV范围[0, 1]
	output.screenUV = float2(
		vertexID <= 1 ? 0.0 : 2.0,
		vertexID == 1 ? 2.0 : 0.0
	);
	if (_ProjectionParams.x < 0.0) {
		output.screenUV.y = 1.0 - output.screenUV.y; //解决某些图形API图形颠倒问题
	}
	return output;
}



//-----------------------------复制片元着色器----------------------------------

float4 CopyPassFragment(Varyings input) : SV_TARGET
{
	return GetSource(input.screenUV);
}



//-----------------------------泛光片元着色器----------------------------------

//泛光滤波器通道
float4 BloomPrefilterPassFragment (Varyings input) : SV_TARGET
{
	float3 color = ApplyBloomThreshold(GetSource(input.screenUV).rgb); //通过阈值，限制泛光影响
	return float4(color, 1.0);
}

//淡化萤火虫效果通道
float4 BloomPrefilterFirefliesPassFragment (Varyings input) : SV_TARGET {
	float3 color = 0.0;
	float weightSum = 0.0;
	float2 offsets[] = {
		float2(0.0, 0.0),
		float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
	};
	for (int i = 0; i < 5; i++)
	{
		float3 c = GetSource(input.screenUV + offsets[i] * GetSourceTexelSize().xy * 2.0).rgb;
		c = ApplyBloomThreshold(c);
		float w = 1.0 / (Luminance(c) + 1.0);
		color += c * w;
		weightSum += w;
	}
	color /= weightSum;
	return float4(color, 1.0);
}

//水平高斯模糊通道
float4 BloomHorizontalPassFragment(Varyings input) : SV_TARGET 
{
	float3 color = 0.0;
	float offsets[] = {
		-4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0
	};
	float weights[] = { //权重源自帕斯卡三角形，避免边缘影响太弱，取第十三行并裁剪掉边缘部分
		0.01621622, 0.05405405, 0.12162162, 0.19459459, 0.22702703,
		0.19459459, 0.12162162, 0.05405405, 0.01621622
	};
	for (int i = 0; i < 9; i++) {
		float offset = offsets[i] * 2.0 * GetSourceTexelSize().x; //计算横向偏移值（由于是从大两倍尺寸纹理采样，所以纹素宽度要放大2倍）
		color += GetSource(input.screenUV + float2(offset, 0.0)).rgb * weights[i];
	}
	return float4(color, 1.0);
}

//垂直高斯模糊通道
float4 BloomVerticalPassFragment(Varyings input) : SV_TARGET 
{
	float3 color = 0.0;
	float offsets[] = {
		-3.23076923, -1.38461538, 0.0, 1.38461538, 3.23076923
	};
	float weights[] = {
		0.07027027, 0.31621622, 0.22702703, 0.31621622, 0.07027027
	};
	for (int i = 0; i < 5; i++) { //使用双线性滤波，适当偏移进行采样，稍微减少样本量
		float offset = offsets[i] * GetSourceTexelSize().y;
		color += GetSource(input.screenUV + float2(0.0, offset)).rgb * weights[i];
	}
	return float4(color, 1.0);
}

//泛光叠加通道
float4 BloomAdditivePassFragmen(Varyings input) : SV_TARGET
{
	float3 lowRes; //低分辨率贴图
	if (_BloomBicubicUpsampling)
	{
		lowRes = GetSourceBicubic(input.screenUV).rgb;
	}
	else
	{
		lowRes = GetSource(input.screenUV).rgb;
	}
	float4 highRes = GetSource2(input.screenUV); //高分辨率贴图
	return float4(lowRes * _BloomIntensity + highRes.rgb, highRes.a); //会使图像变亮
}

//泛光散射通道
float4 BloomScatterPassFragment(Varyings input) : SV_TARGET
{
	float3 lowRes;
	if (_BloomBicubicUpsampling) {
		lowRes = GetSourceBicubic(input.screenUV).rgb;
	}
	else {
		lowRes = GetSource(input.screenUV).rgb;
	}
	float3 highRes = GetSource2(input.screenUV).rgb;
	return float4(lerp(highRes, lowRes, _BloomIntensity), 1.0); //不会使图像变亮
}

//泛光散射最终通道
float4 BloomScatterFinalPassFragment (Varyings input) : SV_TARGET
{
	float3 lowRes;
	if (_BloomBicubicUpsampling) {
		lowRes = GetSourceBicubic(input.screenUV).rgb;
	}
	else {
		lowRes = GetSource(input.screenUV).rgb;
	}
	float4 highRes = GetSource2(input.screenUV);
	lowRes += highRes.rgb - ApplyBloomThreshold(highRes.rgb); //补充丢失的散射光，将缺失的光添加回来
	return float4(lerp(highRes.rgb, lowRes, _BloomIntensity), highRes.a);
}



//-----------------------------色调映射片元着色器----------------------------------

//无色调映射
float4 ToneMappingNonePassFragment (Varyings input) : SV_TARGET
{
	float3 color = GetColorGradedLUT(input.screenUV); 
	return float4(color, 1.0);
}

//ACES色调映射（会影响对比度，色调和饱和度：为非常明亮的颜色添加了色调偏移，将其推向白色；稍微减少较暗颜色，增强对比度）
float4 ToneMappingACESPassFragment (Varyings input) : SV_TARGET
{
	float3 color = GetColorGradedLUT(input.screenUV, true);
	color = AcesTonemap(color);
	return float4(color, 1.0);
}

//中性的色调映射（只希望重新映射， 对色调和饱和度影响最小）
float4 ToneMappingNeutralPassFragment (Varyings input) : SV_TARGET
{
	float3 color = GetColorGradedLUT(input.screenUV);
	color = NeutralTonemap(color); //直接调用SRP Core库NeutralTonemap函数
	return float4(color, 1.0);
}

//莱恩哈德色调映射
float4 ToneMappingReinhardPassFragment (Varyings input) : SV_TARGET
{
	float3 color = GetColorGradedLUT(input.screenUV);
	color /= color + 1.0; //最简单计算方式 c=c/(c+1)
	return float4(color, 1.0);
}



//-----------------------------颜色分级片元着色器----------------------------------

//应用颜色分类
float4 ApplyColorGradingPassFragment (Varyings input) : SV_TARGET
{
	float4 color = GetSource(input.screenUV);
	color.rgb = ApplyColorGradingLUT(color.rgb);
	return color;
}

//应用颜色分类，并且alpha通道用来存储感知亮度
float4 ApplyColorGradingWithLumaPassFragment (Varyings input) : SV_TARGET 
{
	float4 color = GetSource(input.screenUV);
	color.rgb = ApplyColorGradingLUT(color.rgb);
	color.a = sqrt(Luminance(color.rgb)); //亮度的平方，用于近似伽马颜色空间亮度
	return color;
}

//最终还原渲染缩放
float4 FinalPassFragmentRescale (Varyings input) : SV_TARGET
{
	if (_CopyBicubic) {
		return GetSourceBicubic(input.screenUV);
	}
	else {
		return GetSource(input.screenUV);
	}
}

#endif