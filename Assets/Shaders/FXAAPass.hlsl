#ifndef CUSTOM_FXAA_PASS_INCLUDED
#define CUSTOM_FXAA_PASS_INCLUDED

#if defined(FXAA_QUALITY_LOW)
	#define EXTRA_EDGE_STEPS 3
	#define EDGE_STEP_SIZES 1.5, 2.0, 2.0
	#define LAST_EDGE_STEP_GUESS 8.0
#elif defined(FXAA_QUALITY_MEDIUM)
	#define EXTRA_EDGE_STEPS 8
	#define EDGE_STEP_SIZES 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0
	#define LAST_EDGE_STEP_GUESS 8.0
#else
	#define EXTRA_EDGE_STEPS 10
	#define EDGE_STEP_SIZES 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0
	#define LAST_EDGE_STEP_GUESS 8.0
#endif

static const float edgeStepSizes[EXTRA_EDGE_STEPS] = { EDGE_STEP_SIZES };

float4 _FXAAConfig; //x：固定阈值；y：相对阈值；z：亚像素混合系数

//亮度四周数据
struct LumaNeighborhood {
	float m, n, e, s, w, ne, se, sw, nw;
	float highest, lowest, range;
};

//边缘数据
struct FXAAEdge {
	bool isHorizontal; //是否是水平边缘
	float pixelStep; //在UV空间下一个像素的距离
	float lumaGradient, otherLuma; //lumaGradient：亮度变化率，otherLuma：边缘另一侧亮度
};

//是否是水平边缘
bool IsHorizontalEdge (LumaNeighborhood luma)
{
	float horizontal =
		2.0 * abs(luma.n + luma.s - 2.0 * luma.m) +
		abs(luma.ne + luma.se - 2.0 * luma.e) +
		abs(luma.nw + luma.sw - 2.0 * luma.w);
	float vertical =
		2.0 * abs(luma.e + luma.w - 2.0 * luma.m) +
		abs(luma.ne + luma.nw - 2.0 * luma.n) +
		abs(luma.se + luma.sw - 2.0 * luma.s);
	return horizontal >= vertical;
}

//获得边缘数据
FXAAEdge GetFXAAEdge (LumaNeighborhood luma)
{
	FXAAEdge edge;
	edge.isHorizontal = IsHorizontalEdge(luma); //判断边缘是否是水平边缘
	float lumaP, lumaN; //P：正，N：负
	if(edge.isHorizontal)
	{
		edge.pixelStep = GetSourceTexelSize().y;
		lumaP = luma.n;
		lumaN = luma.s;
	}
	else
	{
		edge.pixelStep = GetSourceTexelSize().x;
		lumaP = luma.e;
		lumaN = luma.w;
	}
	float gradientP = abs(lumaP - luma.m); //正亮度变化率
	float gradientN = abs(lumaN - luma.m); //负亮度变化率

	if (gradientP < gradientN) {
		edge.pixelStep = -edge.pixelStep;
		edge.lumaGradient = gradientN; //亮度变化率
		edge.otherLuma = lumaN; //边缘另一侧亮度
	}
	else
	{
		edge.lumaGradient = gradientP; //亮度变化率
		edge.otherLuma = lumaP; //边缘另一侧亮度
	}
	return edge;
}

//获得亮度
float GetLuma (float2 uv, float uOffset = 0.0, float vOffset = 0.0)
{
	uv += float2(uOffset, vOffset) * GetSourceTexelSize().xy;
	#if defined(FXAA_ALPHA_CONTAINS_LUMA)
		return GetSource(uv).a; //如果alpha通道存储了亮度，使用其作为亮度
	#else
		return GetSource(uv).g; //alpha通过没有存储亮度，使用绿色通道作为亮度
	#endif
}

//获得亮度四周数据
LumaNeighborhood GetLumaNeighborhood (float2 uv)
{
	LumaNeighborhood luma;
	luma.m = GetLuma(uv);
	luma.n = GetLuma(uv, 0.0, 1.0);
	luma.e = GetLuma(uv, 1.0, 0.0);
	luma.s = GetLuma(uv, 0.0, -1.0);
	luma.w = GetLuma(uv, -1.0, 0.0);
	luma.ne = GetLuma(uv, 1.0, 1.0);
	luma.se = GetLuma(uv, 1.0, -1.0);
	luma.sw = GetLuma(uv, -1.0, -1.0);
	luma.nw = GetLuma(uv, -1.0, 1.0);
	luma.highest = max(max(max(max(luma.m, luma.n), luma.e), luma.s), luma.w);
	luma.lowest = min(min(min(min(luma.m, luma.n), luma.e), luma.s), luma.w);
	luma.range = luma.highest - luma.lowest;
	return luma;
}

//是否跳过FXAA
bool CanSkipFXAA (LumaNeighborhood luma)
{
	return luma.range < max(_FXAAConfig.x, _FXAAConfig.y * luma.highest); //亮度范围与固定阈值或相对最亮阈值比较，亮度范围小，则不需要FXAA
}

//获得周围3*3亮度混合因子
float GetSubpixelBlendFactor (LumaNeighborhood luma)
{
	float filter = 2.0 * (luma.n + luma.e + luma.s + luma.w);
	filter += luma.ne + luma.nw + luma.se + luma.sw;
	filter *= 1.0 / 12.0; //计算周围亮度加权均值
	filter = abs(filter - luma.m); //与周围亮度加权均值变化率
	filter =  saturate(filter / luma.range); // 片元亮度与周围亮度加权均值变化率越高，越需要进行混合，
	filter = smoothstep(0, 1, filter); //控制范围在0-1，中间值进行平滑阶梯计算
	return filter * filter * _FXAAConfig.z; //最终混合因子，通过平方计算降低强度，通过混合系数来调节混合强度
}

//获得沿边缘混合因子
float GetEdgeBlendFactor (LumaNeighborhood luma, FXAAEdge edge, float2 uv) 
{
	float2 edgeUV = uv;
	float2 uvStep = 0.0;
	if (edge.isHorizontal) {
		edgeUV.y += 0.5 * edge.pixelStep;
		uvStep.x = GetSourceTexelSize().x;
	}
	else
	{
		edgeUV.x += 0.5 * edge.pixelStep;
		uvStep.y = GetSourceTexelSize().y;
	}

	float edgeLuma = 0.5 * (luma.m + edge.otherLuma); //边缘亮度：片元亮度和另一侧亮度平均值
	float gradientThreshold = 0.25 * edge.lumaGradient; //沿边缘亮度变化率阈值：取变化率四分之一

	//沿边缘正方向走
	float2 uvP = edgeUV + uvStep; 
	float lumaDeltaP = GetLuma(uvP) - edgeLuma; //沿边缘亮度变化率
	bool atEndP = abs(lumaDeltaP) >= gradientThreshold; //是否为结束点
	
	int i;
	UNITY_UNROLL
	for (i = 0; i < EXTRA_EDGE_STEPS && !atEndP; i++) {
		uvP += uvStep * edgeStepSizes[i];
		lumaDeltaP = GetLuma(uvP) - edgeLuma;
		atEndP = abs(lumaDeltaP) >= gradientThreshold;
	}
	if (!atEndP) { //如果没有找到结束点，猜测在再LAST_EDGE_STEP_GUESS之后出现结束点
		uvP += uvStep * LAST_EDGE_STEP_GUESS;
	}

	//沿边缘负方向走
	float2 uvN = edgeUV - uvStep;
	float lumaDeltaN = GetLuma(uvN) - edgeLuma;
	bool atEndN = abs(lumaDeltaN) >= gradientThreshold;

	UNITY_UNROLL
	for (i = 0; i < EXTRA_EDGE_STEPS && !atEndN; i++) {
		uvN -= uvStep * edgeStepSizes[i];
		lumaDeltaN = GetLuma(uvN) - edgeLuma;
		atEndN = abs(lumaDeltaN) >= gradientThreshold;
	}
	if (!atEndN) { //如果没有找到结束点，猜测在再LAST_EDGE_STEP_GUESS之后出现结束点
		uvN -= uvStep * LAST_EDGE_STEP_GUESS;
	}

	float distanceToEndP, distanceToEndN; //distanceToEndP：到正方向结束点距离，distanceToEndN：到负方向结束点距离
	if (edge.isHorizontal) {
		distanceToEndP = uvP.x - uv.x;
		distanceToEndN = uv.x - uvN.x;
	}
	else {
		distanceToEndP = uvP.y - uv.y;
		distanceToEndN = uv.y - uvN.y;
	}

	float distanceToNearestEnd; //最近的方向结束点
	bool deltaSign; //增量符号
	if (distanceToEndP <= distanceToEndN) { 
		distanceToNearestEnd = distanceToEndP;
		deltaSign = lumaDeltaP >= 0;
	}
	else {
		distanceToNearestEnd = distanceToEndN;
		deltaSign = lumaDeltaN >= 0;
	}

	if (deltaSign == (luma.m - edgeLuma >= 0)) { //远离边缘，返回0跳过混合
		return 0.0;
	}
	else {
		return 0.5 - distanceToNearestEnd / (distanceToEndP + distanceToEndN);
	}
}

//快速近似抗锯齿通道（原理：）
float4 FXAAPassFragment (Varyings input) : SV_TARGET {
	//1.获得片元周围亮度信息
	LumaNeighborhood luma = GetLumaNeighborhood(input.screenUV); 
	
	//2.判断是否跳过FXAA：根据亮度范围与阈值比较
	if (CanSkipFXAA(luma)) 
	{
		return GetSource(input.screenUV);
	}
	
	//3.计算混合因子（考虑两种方式：亚像素混合、边缘混合）
	FXAAEdge edge = GetFXAAEdge(luma);
	float blendFactor = max(GetSubpixelBlendFactor(luma), GetEdgeBlendFactor (luma, edge, input.screenUV));

	//4.根据混合因子和混合方向，计算最终混合结果
	float2 blendUV = input.screenUV;
	if (edge.isHorizontal) {
		blendUV.y += blendFactor * edge.pixelStep;
	}
	else {
		blendUV.x += blendFactor * edge.pixelStep;
	}
	return GetSource(blendUV);

}

#endif