using Unity.Collections;
using UnityEngine;
using UnityEngine.Experimental.GlobalIllumination;
using LightType = UnityEngine.LightType;
public partial class CustomRenderPipeline
{
    partial void InitializeForEditor ();
	partial void DisposeForEditor ();

#if UNITY_EDITOR
    partial void InitializeForEditor()
    {
		Lightmapping.SetDelegate(lightsDelegate); //设置烘焙光照贴图委托
	}

    partial void DisposeForEditor()
    {
		Lightmapping.ResetDelegate(); //重置烘焙光照贴图委托
	}

	protected override void Dispose (bool disposing) {
		base.Dispose(disposing);
		DisposeForEditor();
		cameraRender.Dispose();
	}

	//烘焙光照贴图委托
	static Lightmapping.RequestLightsDelegate lightsDelegate =
		(Light[] lights, NativeArray<LightDataGI> output) => {
            var lightData = new LightDataGI();
			for (int i = 0; i < lights.Length; i++) {
				Light light = lights[i];
				switch (light.type) {
                    case LightType.Directional:
						var directionalLight = new DirectionalLight();
						LightmapperUtils.Extract(light, ref directionalLight);
						lightData.Init(ref directionalLight);
						break;
					case LightType.Point:
						var pointLight = new PointLight();
						LightmapperUtils.Extract(light, ref pointLight);
						lightData.Init(ref pointLight);
						break;
					case LightType.Spot:
						var spotLight = new SpotLight();
						LightmapperUtils.Extract(light, ref spotLight);
                        spotLight.innerConeAngle = light.innerSpotAngle * Mathf.Deg2Rad;
						spotLight.angularFalloff = AngularFalloffType.AnalyticAndInnerAngle;
						lightData.Init(ref spotLight);
						break;
					case LightType.Area:
						var rectangleLight = new RectangleLight();
						LightmapperUtils.Extract(light, ref rectangleLight);
                        rectangleLight.mode = LightMode.Baked;
						lightData.Init(ref rectangleLight);
						break;
					default:
						lightData.InitNoBake(light.GetInstanceID()); //不烘焙的灯光
						break;
				}
                lightData.falloff = FalloffType.InverseSquared; //设置衰减类型（平方反比）
				output[i] = lightData;
			}
        };

#endif
}
