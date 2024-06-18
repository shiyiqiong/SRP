#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

//指定光源能接收到光照
float3 IncomingLight(Surface surface, Light light)
{
	return saturate(dot(surface.normal, light.direction) * light.attenuation) * light.color; 
}

//获得指定光源直接光照
float3 GetLighting(Surface surface, BRDF brdf, Light light)
{
	return IncomingLight(surface, light) * DirectBRDF(surface, brdf, light);
}

//判断表面渲染层是否处在对应光照渲染层上
bool RenderingLayersOverlap (Surface surface, Light light)
{
	return (surface.renderingLayerMask & light.renderingLayerMask) != 0;
}

//获取所有光照(包括：间接光照和直接光照)
float3 GetLighting(Surface surfaceWS, BRDF brdf, GI gi)
{
	ShadowData shadowData = GetShadowData(surfaceWS);
	shadowData.shadowMask = gi.shadowMask;
	//所有间接光
	float3 color = IndirectBRDF(surfaceWS, brdf, gi.diffuse, gi.specular); 
	//所有方向光源直接光
	for(int i = 0; i < GetDirectionalLightCount(); i++) 
	{
		Light light = GetDirectionalLight(i, surfaceWS, shadowData);
		if(RenderingLayersOverlap(surfaceWS, light)) //判断表面和光照渲染层是否重叠
		{
			color += GetLighting(surfaceWS, brdf, light);
		}
	}
	//所有其他光源直接光
	#if defined(_LIGHTS_PER_OBJECT)
		for(int j = 0; j < min(unity_LightData.y, 8); j++) //只遍历影响物体可见光源，最多受8个光源影响
		{ 
			int lightIndex = unity_LightIndices[(uint)j / 4][(uint)j % 4]; //获取光源索引
			Light light = GetOtherLight(lightIndex, surfaceWS, shadowData);
			if(RenderingLayersOverlap(surfaceWS, light)) //判断表面和光照渲染层是否重叠
			{
				color += GetLighting(surfaceWS, brdf, light);
			}
		}
	#else
		for(int j = 0; j < GetOtherLightCount(); j++) //每个物体都遍历所有可见光源
		{
			Light light = GetOtherLight(j, surfaceWS, shadowData);
			if(RenderingLayersOverlap(surfaceWS, light)) //判断表面和光照渲染层是否重叠
			{
				color += GetLighting(surfaceWS, brdf, light);
			}
		}
	#endif
	return color;
}


#endif