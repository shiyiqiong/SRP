using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

partial class PostFXStack 
{
    
	partial void ApplySceneViewState ();

#if UNITY_EDITOR

	//场景窗口状态发生变化
	partial void ApplySceneViewState()
	{
		if(camera.cameraType == CameraType.SceneView &&
			!SceneView.currentDrawingSceneView.sceneViewState.showImageEffects) // 当场景窗口禁用后处理效果时，不执行后处理
		{
			settings = null;
		}
	}
#endif
}
