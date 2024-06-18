using System;
using UnityEngine;

[System.Serializable]
public struct CameraBufferSettings
{
    public bool allowHDR; //是否开启高动态范围颜色
    public bool copyColor; //是否复制摄像机颜色缓冲区
    public bool copyColorReflection; //是否复制反射探针摄像机颜色缓冲区
    public bool copyDepth; //是否复制摄像机深度缓冲区
    public bool copyDepthReflection; //是否复制反射探针摄像机深度缓冲区

    [Range(0.1f, 2f)]
	public float renderScale; //摄像机缓冲区渲染缩放
    public enum BicubicRescalingMode { Off, UpOnly, UpAndDown } //关闭、仅向上，向上和向下
    public BicubicRescalingMode bicubicRescaling; //双三次插值模式

    [Serializable]
	public struct FXAA {

		public bool enabled;

        [Range(0.0312f, 0.0833f)]
		public float fixedThreshold;

        [Range(0.063f, 0.333f)]
		public float relativeThreshold;

        [Range(0f, 1f)]
		public float subpixelBlending;

        public enum Quality { Low, Medium, High }

		public Quality quality;
	}

	public FXAA fxaa; //快速近似抗锯齿
}