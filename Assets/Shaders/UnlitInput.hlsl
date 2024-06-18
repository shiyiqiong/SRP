#ifndef CUSTOM_UNLIT_INPUT_INCLUDED
#define CUSTOM_UNLIT_INPUT_INCLUDED

#define INPUT_PROP(name) UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, name)

TEXTURE2D(_BaseMap);
TEXTURE2D(_DistortionMap);
SAMPLER(sampler_BaseMap);


UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
	UNITY_DEFINE_INSTANCED_PROP(float, _NearFadeDistance)
	UNITY_DEFINE_INSTANCED_PROP(float, _NearFadeRange)
	UNITY_DEFINE_INSTANCED_PROP(float, _SoftParticlesDistance)
	UNITY_DEFINE_INSTANCED_PROP(float, _SoftParticlesRange)
	UNITY_DEFINE_INSTANCED_PROP(float, _DistortionStrength)
	UNITY_DEFINE_INSTANCED_PROP(float, _DistortionBlend)
	UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
	UNITY_DEFINE_INSTANCED_PROP(float, _ZWrite)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

struct InputConfig
{
	Fragment fragment;
	float4 color;
	float2 baseUV;
	float3 flipbookUVB;
	bool flipbookBlending;
	bool nearFade;
	bool softParticles;
};

InputConfig GetInputConfig(float4 positionSS, float2 baseUV)
{
	InputConfig c;
	c.fragment = GetFragment(positionSS);
	c.color = 1.0;
	c.baseUV = baseUV;
	c.flipbookUVB = 0.0;
	c.flipbookBlending = false;
	c.nearFade = false;
	c.softParticles = false;
	return c;
}

float2 TransformBaseUV (float2 baseUV) {
	float4 baseST = INPUT_PROP(_BaseMap_ST);
	return baseUV * baseST.xy + baseST.zw;
}

float4 GetBase (InputConfig c) {
	float4 baseMap  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, c.baseUV);
	//开启粒子帧动画混合效果（从本帧插值到下一帧）
	if (c.flipbookBlending) {
		baseMap = lerp(
			baseMap, SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, c.flipbookUVB.xy),
			c.flipbookUVB.z
		);
	}
	//开启粒子摄像机近平面淡出效果（近平面淡出衰减：通过视图空间深度预近平面参数进行计算）
	if (c.nearFade) {
		float nearAttenuation = (c.fragment.depth - INPUT_PROP(_NearFadeDistance)) /INPUT_PROP(_NearFadeRange);
		baseMap.a *= saturate(nearAttenuation);
	}
	//开启软粒子效果（软粒子淡出衰减：通过帧缓冲区深度与视图深度差值与软粒子参数进行计算）
	if (c.softParticles) { 
		float depthDelta = c.fragment.bufferDepth - c.fragment.depth;
		float attenuation = (depthDelta - INPUT_PROP(_SoftParticlesDistance)) /
			INPUT_PROP(_SoftParticlesRange);
		baseMap.a *= saturate(attenuation);
	}
	float4 baseColor  = INPUT_PROP(_BaseColor);
	return baseMap * baseColor * c.color;
}

float2 GetDistortion(InputConfig c) 
{
	float4 rawMap = SAMPLE_TEXTURE2D(_DistortionMap, sampler_BaseMap, c.baseUV);
	if (c.flipbookBlending) {
		rawMap = lerp(
			rawMap, SAMPLE_TEXTURE2D(_DistortionMap, sampler_BaseMap, c.flipbookUVB.xy),
			c.flipbookUVB.z
		);
	}
	return DecodeNormal(rawMap, INPUT_PROP(_DistortionStrength)).xy;
}

float GetDistortionBlend (InputConfig c) {
	return INPUT_PROP(_DistortionBlend);
}

float GetCutoff (InputConfig c) {
	return INPUT_PROP(_Cutoff);
}

float GetMetallic (float2 baseUV) {
	return 0.0;
}

float GetSmoothness (float2 baseUV) {
	return 0.0;
}

float GetFresnel (float2 baseUV) {
	return 0.0;
}

float GetFinalAlpha (float alpha) {
	return INPUT_PROP(_ZWrite) ? 1.0 : alpha;
}

#endif