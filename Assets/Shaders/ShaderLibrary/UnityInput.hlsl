#ifndef CUSTOM_UNITY_INPUT_INCLUDED
#define CUSTOM_UNITY_INPUT_INCLUDED



float4x4 unity_MatrixVP;
float4x4 unity_MatrixV;
float4x4 glstate_matrix_projection;

float4x4 unity_MatrixInvV;
float4x4 unity_prev_MatrixM;
float4x4 unity_prev_MatrixIM;

float3 _WorldSpaceCameraPos;

float unity_OneOverOutputBoost;
float unity_MaxOutputValue;
bool4 unity_MetaFragmentControl;

float4 unity_OrthoParams; //正交参数（unity_OrthoParams.w = 0为正交摄像机）
float4 _ProjectionParams; //投影参数（x:是否跌倒投影，y:近平面，z:远平面，w:远平面倒数）
float4 _ScreenParams;
float4 _ZBufferParams;





CBUFFER_START(UnityPerDraw)
	float4x4 unity_ObjectToWorld;
	float4x4 unity_WorldToObject;
	float4 unity_LODFade;
	real4 unity_WorldTransformParams;

	float4 unity_RenderingLayer;

	real4 unity_LightData;
	real4 unity_LightIndices[2];

	float4 unity_ProbesOcclusion;

	float4 unity_SpecCube0_HDR;

	float4 unity_LightmapST;
	float4 unity_DynamicLightmapST;

	float4 unity_SHAr;
	float4 unity_SHAg;
	float4 unity_SHAb;
	float4 unity_SHBr;
	float4 unity_SHBg;
	float4 unity_SHBb;
	float4 unity_SHC;

	float4 unity_ProbeVolumeParams;
	float4x4 unity_ProbeVolumeWorldToObject;
	float4 unity_ProbeVolumeSizeInv;
	float4 unity_ProbeVolumeMin;

CBUFFER_END

#endif