#ifndef CUSTOM_GI_INCLUDED
#define CUSTOM_GI_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

TEXTURE2D(unity_Lightmap); //光照烘焙贴图
SAMPLER(samplerunity_Lightmap); //光照烘焙采样器

TEXTURE2D(unity_ShadowMask); //阴影遮罩贴图
SAMPLER(samplerunity_ShadowMask); //阴影遮罩采样器

TEXTURE3D_FLOAT(unity_ProbeVolumeSH); //光照探针代理体积3D贴图
SAMPLER(samplerunity_ProbeVolumeSH); //光照探针代理体积3D贴图采样器

TEXTURECUBE(unity_SpecCube0); //环境镜面反射立方体贴图
SAMPLER(samplerunity_SpecCube0); //境镜面反射立方体贴图采样器

struct GI
{
	float3 diffuse;
	float3 specular;
	ShadowMask shadowMask;
};

//采样光照贴图
float3 SampleLightMap(float2 lightMapUV)
{
	#if defined(LIGHTMAP_ON)
		return SampleSingleLightmap(
			TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), 
			lightMapUV,
			float4(1.0, 1.0, 0.0, 0.0),
			#if defined(UNITY_LIGHTMAP_FULL_HDR)
				false,
			#else
				true,
			#endif
			float4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0, 0.0)
		);
	#else
		return 0.0;
	#endif
}

//采样光照探针
float3 SampleLightProbe(Surface surfaceWS)
{
	#if defined(LIGHTMAP_ON)
		return 0.0;
	#else
		if(unity_ProbeVolumeParams.x) //光照探针代理体积采样
		{
			return SampleProbeVolumeSH4(
				TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH),
				surfaceWS.position, surfaceWS.normal,
				unity_ProbeVolumeWorldToObject,
				unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z,
				unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz
			);
		}
		else //光照探针采样(包括环境光)
		{
			float4 coefficients[7];
			coefficients[0] = unity_SHAr;
			coefficients[1] = unity_SHAg;
			coefficients[2] = unity_SHAb;
			coefficients[3] = unity_SHBr;
			coefficients[4] = unity_SHBg;
			coefficients[5] = unity_SHBb;
			coefficients[6] = unity_SHC;
			return max(0.0, SampleSH9(coefficients, surfaceWS.normal));
		}
	#endif
}

//采样烘焙阴影
float4 SampleBakedShadows(float2 lightMapUV, Surface surfaceWS)
{
	#if defined(LIGHTMAP_ON)  //烘焙阴影贴图采样
		return SAMPLE_TEXTURE2D(unity_ShadowMask, samplerunity_ShadowMask, lightMapUV);
	#else
		if(unity_ProbeVolumeParams.x) //遮挡探针代理体积采样
		{
			return SampleProbeOcclusion(
				TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH),
				surfaceWS.position, unity_ProbeVolumeWorldToObject,
				unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z,
				unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz
			);
		}
		else //遮挡探针采样
		{
			return unity_ProbesOcclusion;
		}
	#endif
}

inline float3 BoxProjectedCubemapDirection (float3 worldRefl, float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax)
{
    if (cubemapCenter.w > 0.0)
    {
        float3 nrdir = normalize(worldRefl);

        #if 1
            float3 rbmax = (boxMax.xyz - worldPos) / nrdir;
            float3 rbmin = (boxMin.xyz - worldPos) / nrdir;

            float3 rbminmax = (nrdir > 0.0f) ? rbmax : rbmin;

        #else // Optimized version
            float3 rbmax = (boxMax.xyz - worldPos);
            float3 rbmin = (boxMin.xyz - worldPos);

            float3 select = step (float3(0,0,0), nrdir);
            float3 rbminmax = lerp (rbmax, rbmin, select);
            rbminmax /= nrdir;
        #endif

        float fa = min(min(rbminmax.x, rbminmax.y), rbminmax.z);

        worldPos -= cubemapCenter.xyz;
        worldRefl = worldPos + nrdir * fa;
    }
    return worldRefl;
}

//采样环境镜面反射
float3 SampleEnvironment(Surface surfaceWS, BRDF brdf)
{
	float3 uvw = reflect(-surfaceWS.viewDirection, surfaceWS.normal); //通过入射向量和法向量，计算反射向量
	float mip = PerceptualRoughnessToMipmapLevel(brdf.perceptualRoughness); //通过多级渐远纹理，实现不同粗糙度，环境贴图不同模糊效果
	//对立方体环境反射贴图进行采样
	float4 environment = SAMPLE_TEXTURECUBE_LOD(
		unity_SpecCube0, samplerunity_SpecCube0, uvw, mip
	);
	return DecodeHDREnvironment(environment, unity_SpecCube0_HDR); //解码HDR环境光信息
}

//获得全局光照
GI GetGI(float2 lightMapUV, Surface surfaceWS, BRDF brdf)
{
	GI gi;
	//全局光照漫反射
	gi.diffuse = SampleLightMap(lightMapUV) + SampleLightProbe(surfaceWS);
	//全局光照环境镜面反射
	gi.specular = SampleEnvironment(surfaceWS, brdf);
	//预计算阴影遮罩
	gi.shadowMask.always = false;
	gi.shadowMask.distance = false;
	gi.shadowMask.shadows = 1.0;
	#if defined(_SHADOW_MASK_ALWAYS)
		gi.shadowMask.always = true;
		gi.shadowMask.shadows = SampleBakedShadows(lightMapUV, surfaceWS);
	#elif defined(_SHADOW_MASK_DISTANCE)
		gi.shadowMask.distance = true;
		gi.shadowMask.shadows = SampleBakedShadows(lightMapUV, surfaceWS);
	#endif
	return gi;
}

#endif