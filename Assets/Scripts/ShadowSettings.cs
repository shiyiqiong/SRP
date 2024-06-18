using UnityEngine;

[System.Serializable]
public class ShadowSettings 
{
    [Min(0.001f)]
	public float maxDistance = 100f; //方向光最大距离

    [Range(0.001f, 1f)]
	public float distanceFade = 0.1f; //光照淡出
	
    public enum MapSize {_256 = 256, _512 = 512, _1024 = 1024, _2048 = 2048, _4096 = 4096, _8192 = 8192}

    public enum FilterMode { PCF2x2, PCF3x3, PCF5x5, PCF7x7}


    [System.Serializable]
    public struct Directional //方向光阴影设置
    {
        public MapSize atlasSize; //阴影贴图分辨率
        
        public FilterMode filter; //阴影过滤模式

        [Range(1, 4)]
		public int cascadeCount; //阴影级联数量

        [Range(0f, 1f)]
		public float cascadeRatio1, cascadeRatio2, cascadeRatio3; //级联1、2、3比例

        public Vector3 CascadeRatios => new Vector3(cascadeRatio1, cascadeRatio2, cascadeRatio3);

        [Range(0.001f, 1f)]
		public float cascadeFade; //级联淡出

        public enum CascadeBlendMode {Hard, Soft, Dither} //级联混合模式（硬混合、软混合、抖动混合）

        public CascadeBlendMode cascadeBlend; //级联混合模式
    }

    public Directional directional = new Directional {
		atlasSize = MapSize._1024,
        filter = FilterMode.PCF2x2,
        cascadeCount = 4,
		cascadeRatio1 = 0.1f,
		cascadeRatio2 = 0.25f,
		cascadeRatio3 = 0.5f,
        cascadeFade = 0.1f,
        cascadeBlend = Directional.CascadeBlendMode.Hard
	};

    [System.Serializable]
	public struct Other //其他光源阴影设置
    {
		public MapSize atlasSize; //阴影贴图分辨率
		public FilterMode filter; //阴影过滤模式
	}

    public Other other = new Other
    {
		atlasSize = MapSize._1024,
		filter = FilterMode.PCF2x2
	};


    


}
