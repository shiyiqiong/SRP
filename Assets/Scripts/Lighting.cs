using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

public class Lighting 
{
    const string bufferName = "Lighting";

    const int maxDirLightCount = 4; //方向光源最大数量
    static int dirLightCountId  = Shader.PropertyToID("_DirectionalLightCount"); //方向光数量ID
    static int dirLightColorsId  = Shader.PropertyToID("_DirectionalLightColors"); //方向光颜色ID
    static int dirLightDirectionsAndMasksId  = Shader.PropertyToID("_DirectionalLightDirectionsAndMasks"); //方向光方向ID
    static int dirLightShadowDataId = Shader.PropertyToID("_DirectionalLightShadowData"); //方向光阴影数据ID
    static Vector4[] dirLightColors = new Vector4[maxDirLightCount]; 
    static Vector4[] dirLightDirectionsAndMasks = new Vector4[maxDirLightCount];
    static Vector4[] dirLightShadowData = new Vector4[maxDirLightCount];

    const int maxOtherLightCount = 64; //其他光源最大数量
    static int otherLightCountId = Shader.PropertyToID("_OtherLightCount"); //其他光源数量
	static int otherLightColorsId = Shader.PropertyToID("_OtherLightColors"); //其他光源颜色
	static int otherLightPositionsId = Shader.PropertyToID("_OtherLightPositions"); //其他光源位置
    static int otherLightDirectionsAndMasksId = Shader.PropertyToID("_OtherLightDirectionsAndMasks"); //其他光源方向
    static int otherLightSpotAnglesId = Shader.PropertyToID("_OtherLightSpotAngles"); //聚光灯角度
	static int otherLightShadowDataId = Shader.PropertyToID("_OtherLightShadowData"); //其他光阴影数据ID
    static Vector4[] otherLightColors = new Vector4[maxOtherLightCount];
	static Vector4[] otherLightPositions = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightDirectionsAndMasks = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightSpotAngles = new Vector4[maxOtherLightCount];
    static Vector4[] otherLightShadowData = new Vector4[maxOtherLightCount];

    static string lightsPerObjectKeyword = "_LIGHTS_PER_OBJECT";

    CommandBuffer buffer = new CommandBuffer {
        name = bufferName
    };

    CullingResults cullingResults;

    Shadows shadows = new Shadows();

    //设置
    public void Setup(ScriptableRenderContext context, CullingResults cullingResults, ShadowSettings shadowSettings, bool useLightsPerObject, int renderingLayerMask)
    {
        this.cullingResults = cullingResults;
        buffer.BeginSample(bufferName);
        shadows.Setup(context, cullingResults, shadowSettings);
        SetupLight(useLightsPerObject, renderingLayerMask);
        shadows.Render();
        buffer.EndSample(bufferName);
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }

    //设置光源
    void SetupLight(bool useLightsPerObject, int renderingLayerMask)
    {
        int dirLightCount = 0;
        int otherLightCount = 0;
        NativeArray<int> indexMap = useLightsPerObject ? cullingResults.GetLightIndexMap(Allocator.Temp) : default; //光照索引映射
        NativeArray<VisibleLight> visibleLights = cullingResults.visibleLights;
        int i;
        for (i = 0; i < visibleLights.Length; i++)
        {
            int newIndex = -1;
            VisibleLight visibleLight = visibleLights[i];
            Light light = visibleLight.light;
            if((light.renderingLayerMask & renderingLayerMask) != 0)
            {
                switch(visibleLight.lightType)
                {
                    case LightType.Directional:
                        if(dirLightCount < maxDirLightCount)
                        {
                            SetupDirectionalLight(dirLightCount++, i, ref visibleLight, light);
                        }
                        break;
                    case LightType.Point:
                        if(otherLightCount < maxOtherLightCount)
                        {
                            newIndex = otherLightCount;
                            SetupPointLight(otherLightCount++, i, ref visibleLight, light);
                        }
                        break;
                    case LightType.Spot:
                        if(otherLightCount < maxOtherLightCount)
                        {
                            newIndex = otherLightCount;
                            SetupSpotLight(otherLightCount++, i, ref visibleLight, light);
                        }
                        break;
                }
            }
            if(useLightsPerObject)
            {
				indexMap[i] = newIndex; //只设置点光源和聚光灯的索引映射
			}
        }
        if(useLightsPerObject)
        {
			for(; i < indexMap.Length; i++) //剩下其他为不可见光，索引都设置为-1
            {
				indexMap[i] = -1;
			}
            cullingResults.SetLightIndexMap(indexMap); //重新设置光照索引
			indexMap.Dispose();
            Shader.EnableKeyword(lightsPerObjectKeyword);
		}
        else
        {
            Shader.DisableKeyword(lightsPerObjectKeyword);
        }
        buffer.SetGlobalInt(dirLightCountId, dirLightCount);
        if(dirLightCount > 0)
        {
            buffer.SetGlobalVectorArray(dirLightColorsId, dirLightColors);
            buffer.SetGlobalVectorArray(dirLightDirectionsAndMasksId, dirLightDirectionsAndMasks);
            buffer.SetGlobalVectorArray(dirLightShadowDataId, dirLightShadowData);
        }
        buffer.SetGlobalInt(otherLightCountId, otherLightCount);
		if(otherLightCount > 0)
        {
			buffer.SetGlobalVectorArray(otherLightColorsId, otherLightColors);
			buffer.SetGlobalVectorArray(otherLightPositionsId, otherLightPositions);
            buffer.SetGlobalVectorArray(otherLightDirectionsAndMasksId, otherLightDirectionsAndMasks);
            buffer.SetGlobalVectorArray(otherLightSpotAnglesId, otherLightSpotAngles);
            buffer.SetGlobalVectorArray(otherLightShadowDataId, otherLightShadowData);
		}
    }

    //设置方向光源
    void SetupDirectionalLight(int index, int visibleIndex, ref VisibleLight visibleLight, Light light)
    {
        dirLightColors[index] = visibleLight.finalColor;
        Vector4 dirAndMask = -visibleLight.localToWorldMatrix.GetColumn(2);
        dirAndMask.w = light.renderingLayerMask.ReinterpretAsFloat();
        dirLightDirectionsAndMasks[index] = dirAndMask;
        dirLightShadowData[index] = shadows.ReserveDirectionalShadows(light, visibleIndex);
    }

    //设置点光源
    void SetupPointLight(int index, int visibleIndex, ref VisibleLight visibleLight, Light light)
    {
		otherLightColors[index] = visibleLight.finalColor;
        Vector4 position = visibleLight.localToWorldMatrix.GetColumn(3);
		position.w = 1f / Mathf.Max(visibleLight.range * visibleLight.range, 0.00001f);
		otherLightPositions[index] = position;
        otherLightSpotAngles[index] = new Vector4(0f, 1f); //点光源不受聚光角度影响
        Vector4 dirAndmask = Vector4.zero;
        dirAndmask.w = light.renderingLayerMask.ReinterpretAsFloat();
        otherLightDirectionsAndMasks[index] = dirAndmask;

		otherLightShadowData[index] = shadows.ReserveOtherShadows(light, visibleIndex);
	}

    //设置聚光灯
    void SetupSpotLight(int index, int visibleIndex, ref VisibleLight visibleLight, Light light)
    {
		otherLightColors[index] = visibleLight.finalColor;
		Vector4 position = visibleLight.localToWorldMatrix.GetColumn(3);
		position.w = 1f / Mathf.Max(visibleLight.range * visibleLight.range, 0.00001f);
		otherLightPositions[index] = position;
		Vector4 dirAndMask = -visibleLight.localToWorldMatrix.GetColumn(2);
        dirAndMask.w = light.renderingLayerMask.ReinterpretAsFloat();
		otherLightDirectionsAndMasks[index] = dirAndMask;
        
		float innerCos = Mathf.Cos(Mathf.Deg2Rad * 0.5f * light.innerSpotAngle);
		float outerCos = Mathf.Cos(Mathf.Deg2Rad * 0.5f * visibleLight.spotAngle);
		float angleRangeInv = 1f / Mathf.Max(innerCos - outerCos, 0.001f);
		otherLightSpotAngles[index] = new Vector4(angleRangeInv, -outerCos * angleRangeInv);

        otherLightShadowData[index] = shadows.ReserveOtherShadows(light, visibleIndex);
	}

    public void Cleanup()
    {
        shadows.Cleanup();
    }
}
