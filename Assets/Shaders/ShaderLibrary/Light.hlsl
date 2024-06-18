#ifndef CUSTOM_LIGHT_INCLUDED
#define CUSTOM_LIGHT_INCLUDED

#define MAX_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_OTHER_LIGHT_COUNT 64

CBUFFER_START(_CustomLight)
	int _DirectionalLightCount;
	float4 _DirectionalLightColors[MAX_DIRECTIONAL_LIGHT_COUNT];
	float4 _DirectionalLightDirectionsAndMasks[MAX_DIRECTIONAL_LIGHT_COUNT];
	float4 _DirectionalLightShadowData[MAX_DIRECTIONAL_LIGHT_COUNT];

	int _OtherLightCount;
	float4 _OtherLightColors[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightPositions[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightDirectionsAndMasks[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightSpotAngles[MAX_OTHER_LIGHT_COUNT];
	float4 _OtherLightShadowData[MAX_OTHER_LIGHT_COUNT];
CBUFFER_END

struct Light {
	float3 color; //颜色
	float3 direction; //方向
	float attenuation; //衰减
	uint renderingLayerMask; //渲染层遮罩
};

//获取方向光数量
int GetDirectionalLightCount()
{
	return _DirectionalLightCount;
}

//获取方向光阴影数据
DirectionalShadowData GetDirectionalShadowData(int lightIndex, ShadowData shadowData) {
	DirectionalShadowData data;
	data.strength = _DirectionalLightShadowData[lightIndex].x;
	data.tileIndex = _DirectionalLightShadowData[lightIndex].y + shadowData.cascadeIndex;
	data.normalBias = _DirectionalLightShadowData[lightIndex].z;
	data.shadowMaskChannel = _DirectionalLightShadowData[lightIndex].w;
	return data;
}

//获取方向光
Light GetDirectionalLight(int index, Surface surfaceWS, ShadowData shadowData)
{
	Light light;
	light.color = _DirectionalLightColors[index];
	light.direction = _DirectionalLightDirectionsAndMasks[index];
	light.renderingLayerMask = asuint(_DirectionalLightDirectionsAndMasks[index].w);
	DirectionalShadowData dirShadowData  = GetDirectionalShadowData(index, shadowData);
	light.attenuation = GetDirectionalShadowAttenuation(dirShadowData, shadowData, surfaceWS); //受阴影遮挡光照衰减
	return light;
}

//获取其他光源数量
int GetOtherLightCount()
{
	return _OtherLightCount;
}

//获取其他光源阴影数据
OtherShadowData GetOtherShadowData(int lightIndex)
{
	OtherShadowData data;
	data.strength = _OtherLightShadowData[lightIndex].x;
	data.tileIndex = _OtherLightShadowData[lightIndex].y;
	data.shadowMaskChannel = _OtherLightShadowData[lightIndex].w;
	data.isPoint = _OtherLightShadowData[lightIndex].z == 1.0;
	data.lightPositionWS = 0.0;
	data.lightDirectionWS = 0.0;
	data.spotDirectionWS = 0.0;
	return data;
}

//获取其他光源
Light GetOtherLight(int index, Surface surfaceWS, ShadowData shadowData)
{
	Light light;
	
	//光照颜色
	light.color = _OtherLightColors[index].rgb;

	//计算光照方向
	float3 position = _OtherLightPositions[index].xyz;
	float3 ray = position - surfaceWS.position;
	light.direction = normalize(ray);

	//计算光照衰减（包括：距离衰减，范围衰减，聚光角度衰减，阴影衰减）
	float distanceSqr = max(dot(ray, ray), 0.00001);  //距离衰减：平方反比定律
	float rangeAttenuation = Square(saturate(1.0 - Square(distanceSqr * _OtherLightPositions[index].w))); //范围衰减：超出范围平滑衰减为0
	float3 spotDirection = _OtherLightDirectionsAndMasks[index].xyz;
	light.renderingLayerMask = asuint(_OtherLightDirectionsAndMasks[index].w);
	float4 spotAngles = _OtherLightSpotAngles[index];
	float spotAttenuation = Square(
		saturate(dot(spotDirection, light.direction) *
		spotAngles.x + spotAngles.y)
	);  //聚光角度衰减：射到表面光线方向和聚光灯光源朝向夹角，小于聚光灯内角衰减为1，大于聚光灯外角衰减为0，处于内角和外角之间的过渡淡出效果
	OtherShadowData otherShadowData = GetOtherShadowData(index);
	otherShadowData.lightPositionWS = position;
	otherShadowData.lightDirectionWS = light.direction;
	otherShadowData.spotDirectionWS = spotDirection;
	light.attenuation = GetOtherShadowAttenuation(otherShadowData, shadowData, surfaceWS) * spotAttenuation * rangeAttenuation / distanceSqr;
	return light;
}

#endif