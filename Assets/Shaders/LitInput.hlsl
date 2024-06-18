#ifndef CUSTOM_LIT_INPUT_INCLUDED
#define CUSTOM_LIT_INPUT_INCLUDED

#define INPUT_PROP(name) UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, name)

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_EmissionMap);
TEXTURE2D(_MaskMap);
TEXTURE2D(_DetailMap);
SAMPLER(sampler_DetailMap);
TEXTURE2D(_DetailNormalMap);

UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
	UNITY_DEFINE_INSTANCED_PROP(float4, _DetailMap_ST)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
	UNITY_DEFINE_INSTANCED_PROP(float4, _EmissionColor)
	UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
	UNITY_DEFINE_INSTANCED_PROP(float, _ZWrite)
	UNITY_DEFINE_INSTANCED_PROP(float, _Metallic)
	UNITY_DEFINE_INSTANCED_PROP(float, _Occlusion)
	UNITY_DEFINE_INSTANCED_PROP(float, _Smoothness)
	UNITY_DEFINE_INSTANCED_PROP(float, _Fresnel)
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailAlbedo)
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailSmoothness)
	UNITY_DEFINE_INSTANCED_PROP(float, _NormalScale)
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailNormalScale)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

struct InputConfig
{
	Fragment fragment;
	float2 baseUV;
	float2 detailUV;
	bool useMask;
	bool useDetail;
};

InputConfig GetInputConfig(float4 positionSS, float2 baseUV, float2 detailUV = 0.0)
{
	InputConfig c;
	c.fragment = GetFragment(positionSS);
	c.baseUV = baseUV;
	c.detailUV = detailUV;
	c.useMask = false;
	c.useDetail = false;
	return c;
}

//转换基础贴图UV坐标
float2 TransformBaseUV(float2 baseUV)
{
	float4 baseST = INPUT_PROP(_BaseMap_ST);
	return baseUV * baseST.xy + baseST.zw;
}

//转换细节贴图UV坐标
float2 TransformDetailUV(float2 detailUV)
{
	float4 detailST = INPUT_PROP(_DetailMap_ST);
	return detailUV * detailST.xy + detailST.zw;
}

//获取遮罩数据，R：金属性；G：遮挡；B：细节；A：平滑度
float4 GetMask(InputConfig c) {
	if(c.useMask)
	{
		return SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, c.baseUV);
	}
	return 1.0;
}

//获得细节，R：亮或暗；B：光滑或不光滑（范围-1至1）
float4 GetDetail(InputConfig c)
{
	if(c.useDetail)
	{
		float4 map = SAMPLE_TEXTURE2D(_DetailMap, sampler_DetailMap, c.detailUV);
		return map * 2.0 - 1.0; //细节范围从0-1转换为-1-1
	}
	return 0.0;
}

float4 GetBase(InputConfig c)
{
	float4 map = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP(_BaseColor);
	if(c.useDetail)
	{
		float detail = GetDetail(c).r * INPUT_PROP(_DetailAlbedo);
		float mask = GetMask(c).b;
		map.rgb = lerp(sqrt(map.rgb), detail < 0.0 ? 0.0 : 1.0, abs(detail) * mask); //变亮或变暗，通过平方根进行插值近似伽马空间，在伽马空间，亮和暗视觉比较均匀
		map.rgb *= map.rgb;
	}
	return map * color;
}

//获得切线空间法线
float3 GetNormalTS(InputConfig c)
{
	float4 map = SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, c.baseUV); //采样法线贴图
	float scale = INPUT_PROP(_NormalScale); 
	float3 normal = DecodeNormal(map, scale); //解码法线数据
	if(c.useDetail)
	{
		map = SAMPLE_TEXTURE2D(_DetailNormalMap, sampler_DetailMap, c.detailUV);
		scale = INPUT_PROP(_DetailNormalScale) * GetMask(c).b;
		float3 detail = DecodeNormal(map, scale);
		normal = BlendNormalRNM(normal, detail); //混合法线，重新定向法线映射
	}
	return normal;
}

//自发光
float3 GetEmission(InputConfig c)
{
	float4 map = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP(_EmissionColor);
	return map.rgb * color.rgb;
}

float GetCutoff(InputConfig c)
{
	return INPUT_PROP(_Cutoff);
}

//金属
float GetMetallic(InputConfig c)
{
	float metallic = INPUT_PROP(_Metallic);
	metallic *= GetMask(c).r;
	return metallic;
}

//光滑
float GetSmoothness(InputConfig c)
{
	float smoothness = INPUT_PROP(_Smoothness);
	smoothness *= GetMask(c).a;
	if(c.useDetail)
	{
		float detail = GetDetail(c).b * INPUT_PROP(_DetailSmoothness);
		float mask = GetMask(c).b;
		smoothness = lerp(smoothness, detail < 0.0 ? 0.0 : 1.0, abs(detail) * mask);
	}
	return smoothness;
}

//遮挡
float GetOcclusion(InputConfig c)
{
	float strength = INPUT_PROP(_Occlusion);
	float occlusion = GetMask(c).g;
	occlusion = lerp(occlusion, 1.0, strength);
	return occlusion;
}

//菲涅尔
float GetFresnel(InputConfig c)
{
	return INPUT_PROP(_Fresnel);
}

//获得最终透明度
float GetFinalAlpha (float alpha)
{
	return INPUT_PROP(_ZWrite) ? 1.0 : alpha; //到写入深度时，透明度始终为1，或者透明度为alpha
}



#endif