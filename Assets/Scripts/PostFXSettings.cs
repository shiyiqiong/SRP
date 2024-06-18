using System;
using UnityEngine;

[CreateAssetMenu(menuName = "Rendering/Custom Post FX Settings")]
public class PostFXSettings : ScriptableObject
{
    [SerializeField]
	Shader shader = default; //后处理着色器（包括：光晕、色调映射、颜色分级、快速近似抗锯齿）

    [System.NonSerialized]
	Material material; //后处理材质

	public Material Material {
		get {
			if (material == null && shader != null) {
				material = new Material(shader);
				material.hideFlags = HideFlags.HideAndDontSave;
			}
			return material;
		}
	}


//光晕
    [System.Serializable]
	public struct BloomSettings {
		public bool ignoreRenderScale;

		[Range(0f, 16f)]
		public int maxIterations;

		[Min(1f)]
		public int downscaleLimit;

        public bool bicubicUpsampling;

        [Min(0f)]
		public float threshold;

		[Range(0f, 1f)]
		public float thresholdKnee;

        [Min(0f)]
		public float intensity;

		public bool fadeFireflies;

		public enum Mode { Additive, Scattering }

		public Mode mode;

		[Range(0.05f, 0.95f)]
		public float scatter;
	}

	[SerializeField]
	BloomSettings bloom = new BloomSettings {
		scatter = 0.7f
	};

	public BloomSettings Bloom => bloom;


//颜色调整
	[Serializable]
	public struct ColorAdjustmentsSettings {
		public float postExposure; //曝光

		[Range(-100f, 100f)]
		public float contrast; //对比度

		[ColorUsage(false, true)]
		public Color colorFilter; //颜色过滤器

		[Range(-180f, 180f)]
		public float hueShift; //色调偏移

		[Range(-100f, 100f)]
		public float saturation; //饱和度
	}

	[SerializeField]
	ColorAdjustmentsSettings colorAdjustments = new ColorAdjustmentsSettings {
		colorFilter = Color.white
	};

	public ColorAdjustmentsSettings ColorAdjustments => colorAdjustments;


//白平衡
	[Serializable]
	public struct WhiteBalanceSettings {

		[Range(-100f, 100f)]
		public float temperature, tint; //temperature：色温，tint：补偿绿色或洋红色
	}

	[SerializeField]
	WhiteBalanceSettings whiteBalance = default;

	public WhiteBalanceSettings WhiteBalance => whiteBalance;


//拆分着色
	[Serializable]
	public struct SplitToningSettings {

		[ColorUsage(false)]
		public Color shadows, highlights; //shadows：用于阴影着色的颜色，highlights：用于高光着色的颜色

		[Range(-100f, 100f)]
		public float balance; //设置阴影和高光着色平衡，较小值阴影明显，较大值高光明显
	}

	[SerializeField]
	SplitToningSettings splitToning = new SplitToningSettings {
		shadows = Color.gray,
		highlights = Color.gray
	};

	public SplitToningSettings SplitToning => splitToning;


//通道混合器
[Serializable]
	public struct ChannelMixerSettings {

		public Vector3 red, green, blue; //red：红色通道对所选输出通道的影响，green：绿色通道对所选输出通道的影响；blue：蓝色通道对所选输出通道影响
	}
	
	[SerializeField]
	ChannelMixerSettings channelMixer = new ChannelMixerSettings {
		red = Vector3.right,
		green = Vector3.up,
		blue = Vector3.forward
	};

	public ChannelMixerSettings ChannelMixer => channelMixer;


//阴影、中间色调、高光
	[Serializable]
	public struct ShadowsMidtonesHighlightsSettings {

		[ColorUsage(false, true)]
		public Color shadows, midtones, highlights; //shadows：控制阴影颜色，midtones：控制中间色调颜色，highlights：控制高光颜色

		[Range(0f, 2f)]
		public float shadowsStart, shadowsEnd, highlightsStart, highLightsEnd; //shadowsStart：阴影和中间色调过渡起点，shadowsEnd：阴影和中间色调过渡终点，highlightsStart：中间色调和高光过渡起点，highLightsEnd：中间色调和高光过渡终点
	}

	[SerializeField]
	ShadowsMidtonesHighlightsSettings
		shadowsMidtonesHighlights = new ShadowsMidtonesHighlightsSettings {
			shadows = Color.white,
			midtones = Color.white,
			highlights = Color.white,
			shadowsEnd = 0.3f,
			highlightsStart = 0.55f,
			highLightsEnd = 1f
		};

	public ShadowsMidtonesHighlightsSettings ShadowsMidtonesHighlights =>
		shadowsMidtonesHighlights;


//色调映射
	[System.Serializable]
	public struct ToneMappingSettings {

		public enum Mode { None, ACES, Neutral, Reinhard }

		public Mode mode;
	}

	[SerializeField]
	ToneMappingSettings toneMapping = default;

	public ToneMappingSettings ToneMapping => toneMapping;


}
