using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[CreateAssetMenu(menuName = "Rendering/ExampleRenderPipelineAsset")]
public class ExampleRenderPipelineAsset : RenderPipelineAsset
{
    public Color exampleColor;
    public string exampleString;


    protected override RenderPipeline CreatePipeline() {
        // 实例化此自定义 SRP 用于渲染的渲染管线。
        return new ExampleRenderPipelineInstance(this);
    }
}
