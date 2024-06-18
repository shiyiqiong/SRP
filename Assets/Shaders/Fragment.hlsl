#ifndef FRAGMENT_INCLUDED
#define FRAGMENT_INCLUDED

TEXTURE2D(_CameraColorTexture);
TEXTURE2D(_CameraDepthTexture);

float4 _CameraBufferSize;

struct Fragment {
	float2 positionSS;
	float2 screenUV;
	float depth;
	float bufferDepth;
};

Fragment GetFragment(float4 positionSS)
{
	Fragment f;
	f.positionSS = positionSS.xy; //屏幕空间XY坐标：X[0, 屏幕像素宽度]，Y[0, 屏幕像素高度]
	f.screenUV = f.positionSS * _CameraBufferSize.xy; //视口空间XY坐标：X[0, 1]，Y[0, 1]
	f.depth = IsOrthographicCamera() ? OrthographicDepthBufferToLinear(positionSS.z) : positionSS.w; //视图空间深度[近平面， 远平面]
	f.bufferDepth = SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, sampler_point_clamp, f.screenUV, 0); //采样帧缓冲区深度[近平面：1，远平面为：0]
	f.bufferDepth = IsOrthographicCamera() ? OrthographicDepthBufferToLinear(f.bufferDepth) : LinearEyeDepth(f.bufferDepth, _ZBufferParams); //帧缓冲区深度转换为视图空间深度[近平面， 远平面]
	return f;
}

//对缓冲区颜色进行采样
float4 GetBufferColor(Fragment fragment, float2 uvOffset = float2(0.0, 0.0))
{
	float2 uv = fragment.screenUV + uvOffset;
	return SAMPLE_TEXTURE2D_LOD(_CameraColorTexture, sampler_linear_clamp, uv, 0);
}

#endif