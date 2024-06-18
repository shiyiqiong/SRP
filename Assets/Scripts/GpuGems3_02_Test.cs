using System.Collections;
using System.Collections.Generic;
using UnityEngine;


public class GpuGems3_02_Test : MonoBehaviour
{
    
    public GameObject go;
    private MaterialPropertyBlock block;

    private void Awake()
    {
        block = new MaterialPropertyBlock();
        if(go == null) return;
        for(int i = 0; i < 100; i++)
        {
            Vector3 pos = new Vector3(Random.Range(-50f, 50f), 0, Random.Range(-50f, 50f));
            GameObject instante = Instantiate<GameObject>(go, pos, Quaternion.identity);
            block.SetColor("_BaseColor", new Color(Random.Range(0f, 1f), Random.Range(0f, 1f), Random.Range(0f, 1f), 1f));
            instante.GetComponent<MeshRenderer>().SetPropertyBlock(block);
        }
    }

}
