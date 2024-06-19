using System;
using UnityEngine;
using UnityEngine.Rendering;

[Serializable]
public class CameraSettings {
	public bool copyColor = true; //是否复制摄像机颜色缓冲区
	public bool copyDepth = true; //是否复制摄像机深度缓冲区

	[RenderingLayerMaskField]
	public int renderingLayerMask = -1; //渲染层级遮罩

	public bool maskLights = false; //是否启用灯光遮罩

	public enum RenderScaleMode { Inherit, Multiply, Override } //渲染缩放模式（继承，相乘，覆盖）

	public RenderScaleMode renderScaleMode = RenderScaleMode.Inherit; //渲染缩放模式

	[Range(0.1f, 2f)]
	public float renderScale = 1f; //渲染缩放

	public bool overridePostFX = false; //是否覆盖后处理

	public PostFXSettings postFXSettings = default; //后处理设置

	public bool allowFXAA = false; //是否启用快速近似抗锯齿

	public bool keepAlpha = false; //是否保留Alpha通道（当多个摄像机堆叠是需要保留透明通道）

	[Serializable]
	public struct FinalBlendMode {

		public BlendMode source, destination;
	}

	public FinalBlendMode finalBlendMode = new FinalBlendMode { //摄像机最终混合模式（仅对摄像机堆叠有意义）
		source = BlendMode.One,
		destination = BlendMode.Zero
	};


	public float GetRenderScale (float scale)
	{
		return renderScaleMode == RenderScaleMode.Inherit ? scale :
			renderScaleMode == RenderScaleMode.Override ? renderScale :
			scale * renderScale;
	}
    
}

