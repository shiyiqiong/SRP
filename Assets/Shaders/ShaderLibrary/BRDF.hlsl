#ifndef CUSTOM_BRDF_INCLUDED
#define CUSTOM_BRDF_INCLUDED

#define MIN_REFLECTIVITY 0.04

struct BRDF 
{
	float3 diffuse; //漫反射
	float3 specular; //镜面反射
	float roughness; //粗糙度
	float perceptualRoughness; //感知粗糙度
	float fresnel; //菲涅尔反射
};

//1减于反射率（0-0.96）
float OneMinusReflectivity(float metallic)
{
	float range = 1.0 - MIN_REFLECTIVITY;
	return range - metallic*range;
}

//间接光双向反射分布函数
float3 IndirectBRDF(Surface surface, BRDF brdf, float3 diffuse, float3 specular)
{
	float fresnelStrength = surface.fresnelStrength * Pow4(1.0 - saturate(dot(surface.normal, surface.viewDirection))); //菲涅尔反射强度
	float3 reflection = specular * lerp(brdf.specular, brdf.fresnel, fresnelStrength); //环境光镜面反射，考虑材质金属性镜面反射和菲涅尔反射
	reflection /= brdf.roughness * brdf.roughness + 1.0; //粗糙度对环境光镜面反射影响，最大粗糙度使反射减半，最小粗糙度对反射没有影响
    return (diffuse * brdf.diffuse + reflection) * surface.occlusion;
}

//获得双向反射分布函数信息
BRDF GetBRDF(Surface surface, bool applyAlphaToDiffuse = false)
{
	BRDF brdf;
	float oneMinusReflectivity = OneMinusReflectivity(surface.metallic);
	brdf.diffuse = surface.color * oneMinusReflectivity;
	if(applyAlphaToDiffuse)
	{
		brdf.diffuse *= surface.alpha;
	}
	brdf.specular = lerp(MIN_REFLECTIVITY, surface.color, surface.metallic);
	brdf.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(surface.smoothness);
	brdf.roughness = PerceptualRoughnessToRoughness(brdf.perceptualRoughness);
	brdf.fresnel = saturate(surface.smoothness + 1.0 - oneMinusReflectivity); //菲涅尔反射，表面平滑度加反射率
	return brdf;
}

//直接光镜面反射强度
float SeqcularStrength(Surface surface, BRDF brdf, Light light)
{
	float3 h = SafeNormalize(light.direction + surface.viewDirection);
	float nh2 = Square(saturate(dot(surface.normal, h)));
	float lh2 = Square(saturate(dot(light.direction, h)));
	float r2 = Square(brdf.roughness);
	float d2 = Square(nh2 * (r2 - 1.0) + 1.00001);
	float normalization = brdf.roughness *4.0 + 2.0;
	return r2 / (d2 * max(0.1, lh2) * normalization);
}

//直接光双向反射分布函数
float3 DirectBRDF(Surface surface, BRDF brdf, Light light)
{
	return SeqcularStrength(surface, brdf, light) * brdf.specular + brdf.diffuse;
}

#endif