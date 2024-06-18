using UnityEngine;

[DisallowMultipleComponent, RequireComponent(typeof(Camera))]
public class CustomRenderPipelineCamera : MonoBehaviour {

	[SerializeField]
	CameraSettings settings = default;

	public CameraSettings Settings => settings ?? (settings = new CameraSettings()); //??运算符：null合并运算符，如果左边不为null返回左边操作数，否则返回右边操作数
}
