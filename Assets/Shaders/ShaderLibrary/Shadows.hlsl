#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"

#if defined(_DIRECTIONAL_PCF3)
	#define DIRECTIONAL_FILTER_SAMPLES 4
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
	#define DIRECTIONAL_FILTER_SAMPLES 9
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
	#define DIRECTIONAL_FILTER_SAMPLES 16
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#if defined(_OTHER_PCF3)
	#define OTHER_FILTER_SAMPLES 4
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_OTHER_PCF5)
	#define OTHER_FILTER_SAMPLES 9
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_OTHER_PCF7)
	#define OTHER_FILTER_SAMPLES 16
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_SHADOWED_OTHER_LIGHT_COUNT 16
#define MAX_CASCADE_COUNT 4

TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
TEXTURE2D_SHADOW(_OtherShadowAtlas);
#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);

CBUFFER_START(_CustomShadows)
    int _CascadeCount;
	float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
    float4 _CascadeData[MAX_CASCADE_COUNT];
	float4x4 _DirectionalShadowMatrices[MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
	float4x4 _OtherShadowMatrices[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _OtherShadowTiles[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _ShadowAtlasSize;
    float4 _ShadowDistanceFade;
CBUFFER_END

struct ShadowMask  //阴影遮罩
{
	bool always; 
	bool distance;
	float4 shadows;
};

struct ShadowData //全局阴影数据
{
	int cascadeIndex;
	float cascadeBlend;
    float strength; //最大阴影距离淡出效果阴影强度
	ShadowMask shadowMask;
};

struct DirectionalShadowData //指定方向光阴影数据
{
	float strength;	//方向光设置的阴影强度
	int tileIndex;
    float normalBias;
	int shadowMaskChannel;
};

struct OtherShadowData //指定其他光阴影数据
{
	float strength; //其他光设置阴影强度
	int tileIndex;
	bool isPoint;
	int shadowMaskChannel;
	float3 lightPositionWS;
	float3 lightDirectionWS;
	float3 spotDirectionWS;
};

//计算阴影淡出
float FadedShadowStrength(float distance, float scale, float fade)
{
	return saturate((1.0 - distance * scale) * fade);
}

//获取阴影数据
ShadowData GetShadowData(Surface surfaceWS)
{
	ShadowData data;
	data.shadowMask.always = false;
	data.shadowMask.distance = false;
	data.shadowMask.shadows = 1.0;
	data.cascadeBlend = 1.0;
    data.strength = FadedShadowStrength(surfaceWS.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y); //根据最大阴影距离进行剔除，并且具有淡出效果
    int i;
    //选择最佳级联
	for(i = 0; i < _CascadeCount; i++)
    {
		float4 sphere = _CascadeCullingSpheres[i];
		float distanceSqr = DistanceSquared(surfaceWS.position, sphere.xyz);
		if (distanceSqr < sphere.w) {
			float fade = FadedShadowStrength(distanceSqr, _CascadeData[i].x, _ShadowDistanceFade.z); //级联过渡效果
            if(i == _CascadeCount - 1)
            {
				data.strength *= fade;
			}
			else
			{
				data.cascadeBlend = fade;
			}
			break;
		}
	}
    if(i == _CascadeCount && _CascadeCount > 0) //如果有设置级联（无方向光时，_CascadeCount为0），并且超出最后级联
    {
        data.strength = 0.0; //不需要对实时阴影进行采样
    }
	#if defined(_CASCADE_BLEND_DITHER)
		else if (data.cascadeBlend < surfaceWS.dither) {
			i += 1;
		}
	#endif
	#if !defined(_CASCADE_BLEND_SOFT)
		data.cascadeBlend = 1.0;
	#endif
	data.cascadeIndex = i;
	return data;
}

//采样方向光阴影贴图集
float SampleDirectionalShadowAtlas(float3 positionSTS)
{
	return SAMPLE_TEXTURE2D_SHADOW(_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS);
}

//采样其他光阴影贴图集
float SampleOtherShadowAtlas(float3 positionSTS, float3 bounds)
{
	positionSTS.xy = clamp(positionSTS.xy, bounds.xy, bounds.xy + bounds.z); //采集点限制在阴影贴图范围内
	return SAMPLE_TEXTURE2D_SHADOW(_OtherShadowAtlas, SHADOW_SAMPLER, positionSTS);
}

//方向光阴影过滤器
float FilterDirectionalShadow(float3 positionSTS)
{
	#if defined(DIRECTIONAL_FILTER_SETUP)
		float weights[DIRECTIONAL_FILTER_SAMPLES];
		float2 positions[DIRECTIONAL_FILTER_SAMPLES];
		float4 size = _ShadowAtlasSize.yyxx;
		DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
		float shadow = 0;
		for(int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++)
		{
			shadow += weights[i] * SampleDirectionalShadowAtlas(float3(positions[i].xy, positionSTS.z));
		}
		return shadow;
	#else
		return SampleDirectionalShadowAtlas(positionSTS);
	#endif
}

float FilterOtherShadow(float3 positionSTS, float3 bounds)
{
	#if defined(OTHER_FILTER_SETUP)
		float weights[OTHER_FILTER_SAMPLES];
		float2 positions[OTHER_FILTER_SAMPLES];
		float4 size = _ShadowAtlasSize.wwzz;
		OTHER_FILTER_SETUP(size, positionSTS.xy, weights, positions);
		float shadow = 0;
		for(int i = 0; i < OTHER_FILTER_SAMPLES; i++)
		{
			shadow += weights[i] * SampleOtherShadowAtlas(float3(positions[i].xy, positionSTS.z), bounds);
		}
		return shadow;
	#else
		return SampleOtherShadowAtlas(positionSTS, bounds);
	#endif
}


//获得方向光实时级联阴影
float GetCascadedShadow(DirectionalShadowData directional, ShadowData global, Surface surfaceWS)
{
	float3 normalBias = surfaceWS.interpolatedNormal * (directional.normalBias *_CascadeData[global.cascadeIndex].y); //法线偏差 = 表面归一化法线 * 光源设置法线偏差 * 计算出阴影贴图一个像素最长距离
	float3 positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex], float4(surfaceWS.position + normalBias, 1.0)).xyz;  //surfaceWS.position + normalBias：沿着法线偏差，稍微移动表面位置，来实现阴影采样
	float shadow = FilterDirectionalShadow(positionSTS);
	if(global.cascadeBlend < 1.0) //判断是否需要做级联混合
	{
		normalBias = surfaceWS.interpolatedNormal * (directional.normalBias * _CascadeData[global.cascadeIndex + 1].y);
		positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex + 1], float4(surfaceWS.position + normalBias, 1.0)).xyz;
		shadow = lerp(FilterDirectionalShadow(positionSTS), shadow, global.cascadeBlend); //级联混合从1至0，从当前级联插值至下个级联
	}
	return shadow;
}

//获得烘焙贴图阴影
float GetBakedShadow(ShadowMask mask, int channel)
{
	float shadow = 1.0;
	if(mask.always || mask.distance)
	{
		if(channel >= 0)
		{
			shadow = mask.shadows[channel];
		}
	}
	return shadow;
}

//获得烘焙贴图阴影，通过阴影强度进行插值
float GetBakedShadow(ShadowMask mask, int channel, float strength)
{
	if(mask.always || mask.distance)
	{
		return lerp(1.0, GetBakedShadow(mask, channel), strength);
	}
	return 1.0;
}

//混合烘焙阴影和实时阴影
float MixBakedAndRealtimeShadows(ShadowData global, float shadow, int shadowMaskChannel, float strength)
{
	float baked = GetBakedShadow(global.shadowMask, shadowMaskChannel);
	if (global.shadowMask.always) { //阴影遮挡类型：shadowmask
		shadow = lerp(1.0, shadow, global.strength);
		shadow = min(baked, shadow);
		return lerp(1.0, shadow, strength);
	}
	if(global.shadowMask.distance) //阴影遮挡类型：distance shadowmask
	{
		shadow = lerp(baked, shadow, global.strength);
		return lerp(1.0, shadow, strength);
	}
	return lerp(1.0, shadow, strength * global.strength);
}

//获取方向光阴影衰减
float GetDirectionalShadowAttenuation(DirectionalShadowData directional, ShadowData global, Surface surfaceWS)
{
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
	float shadow;
    if (directional.strength * global.strength <= 0.0) //超过最大阴影距离，只计算烘焙阴影（directional.strength：阴影强度 global.strength：根据最大阴影距离和淡出过程效果，计算阴影强度）
    {
		shadow = GetBakedShadow(global.shadowMask, directional.shadowMaskChannel, abs(directional.strength));  //directional.strength为负时，场景没有受光照阴影投射对象，只计算烘焙阴影
	}
	else //计算实时阴影与烘焙阴影混合
	{
		shadow = GetCascadedShadow(directional, global, surfaceWS);
		shadow = MixBakedAndRealtimeShadows(global, shadow, directional.shadowMaskChannel, directional.strength);
	}
	return shadow;
}

static const float3 pointShadowPlanes[6] = {
	float3(-1.0, 0.0, 0.0),
	float3(1.0, 0.0, 0.0),
	float3(0.0, -1.0, 0.0),
	float3(0.0, 1.0, 0.0),
	float3(0.0, 0.0, -1.0),
	float3(0.0, 0.0, 1.0)
};

//获得其他光照实时阴影
float GetOtherShadow(OtherShadowData other, ShadowData global, Surface surfaceWS)
{
	float tileIndex = other.tileIndex;
	float3 lightPlane = other.spotDirectionWS;
	if (other.isPoint)
	{
		float faceOffset = CubeMapFaceID(-other.lightDirectionWS); //通过光线方向，获得立方体面ID，作为偏移值
		tileIndex += faceOffset;  //通过偏移值计算阴影贴图索引
		lightPlane = pointShadowPlanes[faceOffset]; //通过偏移值获得点光源光平面

	}
	float4 tileData = _OtherShadowTiles[tileIndex];
	float3 surfaceToLight = other.lightPositionWS - surfaceWS.position;
	float distanceToLightPlane = dot(surfaceToLight, lightPlane);
	float3 normalBias = surfaceWS.interpolatedNormal * (distanceToLightPlane * tileData.w); //法线偏差 = 表面归一化法线 * 
	float4 positionSTS = mul(
		_OtherShadowMatrices[tileIndex],
		float4(surfaceWS.position + normalBias, 1.0)
	);
	return FilterOtherShadow(positionSTS.xyz / positionSTS.w, tileData.xyz);
}

//获取其他光阴影衰减
float GetOtherShadowAttenuation(OtherShadowData other, ShadowData global, Surface surfaceWS)
{
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
	
	float shadow;
	if (other.strength * global.strength <= 0.0) {
		shadow = GetBakedShadow(global.shadowMask, other.shadowMaskChannel, abs(other.strength));
	}
	else {
		shadow = GetOtherShadow(other, global, surfaceWS);
		shadow = MixBakedAndRealtimeShadows(global, shadow, other.shadowMaskChannel, other.strength);
	}
	return shadow;
}



#endif