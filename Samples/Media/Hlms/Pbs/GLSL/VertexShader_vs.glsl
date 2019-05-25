@insertpiece( SetCrossPlatformSettings )
@insertpiece( SetCompatibilityLayer )

out gl_PerVertex
{
	vec4 gl_Position;
@property( hlms_global_clip_planes )
	float gl_ClipDistance[@value(hlms_global_clip_planes)];
@end
};

layout(std140) uniform;

@insertpiece( Common_Matrix_DeclUnpackMatrix4x4 )
@insertpiece( Common_Matrix_DeclUnpackMatrix3x4 )

in vec4 vertex;

@property( hlms_normal )in vec3 normal;@end
@property( hlms_qtangent )in vec4 qtangent;@end

@property( normal_map && !hlms_qtangent )
in vec3 tangent;
@property( hlms_binormal )in vec3 binormal;@end
@end

@property( hlms_skeleton )
in uvec4 blendIndices;
in vec4 blendWeights;@end

@foreach( hlms_uv_count, n )
in vec@value( hlms_uv_count@n ) uv@n;@end

@property( GL_ARB_base_instance )
	in uint drawId;
@end

@insertpiece( custom_vs_attributes )

@property( !hlms_shadowcaster || !hlms_shadow_uses_depth_texture || alpha_test || exponential_shadow_maps )
out block
{
@insertpiece( VStoPS_block )
} outVs;
@end

// START UNIFORM DECLARATION
@insertpiece( PassDecl )
@property( hlms_skeleton || hlms_shadowcaster || hlms_pose )@insertpiece( InstanceDecl )@end
/*layout(binding = 0) */uniform samplerBuffer worldMatBuf;
@insertpiece( custom_vs_uniformDeclaration )
@property( !GL_ARB_base_instance )uniform uint baseInstance;@end
@property( hlms_pose )
	uniform samplerBuffer poseBuf;
@end
// END UNIFORM DECLARATION

@property( hlms_qtangent )
@insertpiece( DeclQuat_xAxis )
@property( normal_map )
@insertpiece( DeclQuat_yAxis )
@end @end

@property( !hlms_pose )
@piece( input_vertex )vertex@end
@end
@property( hlms_pose )
@piece( input_vertex )inputPos@end
@end

@property( !hlms_skeleton )
@piece( local_vertex )@insertpiece( input_vertex )@end
@piece( local_normal )normal@end
@piece( local_tangent )tangent@end
@end
@property( hlms_skeleton )
@piece( local_vertex )worldPos@end
@piece( local_normal )worldNorm@end
@piece( local_tangent )worldTang@end
@end

@property( hlms_skeleton )@piece( SkeletonTransform )
	uint _idx = (blendIndices[0] << 1u) + blendIndices[0]; //blendIndices[0] * 3u; a 32-bit int multiply is 4 cycles on GCN! (and mul24 is not exposed to GLSL...)
		uint matStart = instance.worldMaterialIdx[drawId].x >> 9u;
	vec4 worldMat[3];
		worldMat[0] = bufferFetch( worldMatBuf, int(matStart + _idx + 0u) );
		worldMat[1] = bufferFetch( worldMatBuf, int(matStart + _idx + 1u) );
		worldMat[2] = bufferFetch( worldMatBuf, int(matStart + _idx + 2u) );
    vec4 worldPos;
    worldPos.x = dot( worldMat[0], @insertpiece( input_vertex ) );
    worldPos.y = dot( worldMat[1], @insertpiece( input_vertex ) );
    worldPos.z = dot( worldMat[2], @insertpiece( input_vertex ) );
    worldPos.xyz *= blendWeights[0];
    @property( hlms_normal || hlms_qtangent )vec3 worldNorm;
    worldNorm.x = dot( worldMat[0].xyz, normal );
    worldNorm.y = dot( worldMat[1].xyz, normal );
    worldNorm.z = dot( worldMat[2].xyz, normal );
    worldNorm *= blendWeights[0];@end
    @property( normal_map )vec3 worldTang;
    worldTang.x = dot( worldMat[0].xyz, tangent );
    worldTang.y = dot( worldMat[1].xyz, tangent );
    worldTang.z = dot( worldMat[2].xyz, tangent );
    worldTang *= blendWeights[0];@end

	@psub( NeedsMoreThan1BonePerVertex, hlms_bones_per_vertex, 1 )
	@property( NeedsMoreThan1BonePerVertex )vec4 tmp;
	tmp.w = 1.0;@end //!NeedsMoreThan1BonePerVertex
	@foreach( hlms_bones_per_vertex, n, 1 )
	_idx = (blendIndices[@n] << 1u) + blendIndices[@n]; //blendIndices[@n] * 3; a 32-bit int multiply is 4 cycles on GCN! (and mul24 is not exposed to GLSL...)
		worldMat[0] = bufferFetch( worldMatBuf, int(matStart + _idx + 0u) );
		worldMat[1] = bufferFetch( worldMatBuf, int(matStart + _idx + 1u) );
		worldMat[2] = bufferFetch( worldMatBuf, int(matStart + _idx + 2u) );
	tmp.x = dot( worldMat[0], @insertpiece( input_vertex ) );
	tmp.y = dot( worldMat[1], @insertpiece( input_vertex ) );
	tmp.z = dot( worldMat[2], @insertpiece( input_vertex ) );
	worldPos.xyz += (tmp * blendWeights[@n]).xyz;
	@property( hlms_normal || hlms_qtangent )
	tmp.x = dot( worldMat[0].xyz, normal );
	tmp.y = dot( worldMat[1].xyz, normal );
	tmp.z = dot( worldMat[2].xyz, normal );
    worldNorm += tmp.xyz * blendWeights[@n];@end
	@property( normal_map )
	tmp.x = dot( worldMat[0].xyz, tangent );
	tmp.y = dot( worldMat[1].xyz, tangent );
	tmp.z = dot( worldMat[2].xyz, tangent );
    worldTang += tmp.xyz * blendWeights[@n];@end
	@end

	worldPos.w = 1.0;
@end @end //SkeletonTransform // !hlms_skeleton

@property( hlms_pose )@piece( PoseTransform )
	// Pose data starts after all 3x4 bone matrices
	int poseDataStart = int(instance.worldMaterialIdx[drawId].x >> 9u) @property( hlms_skeleton ) + @value(hlms_bones_per_vertex) * 3@end ;
	vec4 inputPos = vertex;

	vec4 poseData = bufferFetch( worldMatBuf, poseDataStart );
	int baseVertexID = floatBitsToInt( poseData.x );
	int vertexID = gl_VertexID - baseVertexID;
	vec4 poseWeights = bufferFetch( worldMatBuf, poseDataStart + 1 );

	@psub( MoreThanOnePose, hlms_pose, 1 )
	@property( !MoreThanOnePose )
		vec4 posePos = bufferFetch( poseBuf, vertexID );
		inputPos += posePos * poseWeights.x;
	@end @property( MoreThanOnePose )
		int numVertices = floatBitsToInt( poseData.y );
		vec4 posePos;
		@foreach( hlms_pose, n )
			posePos = bufferFetch( poseBuf, vertexID + numVertices * @n );
			inputPos += posePos * poseWeights[@n];
		@end
	@end

	// If hlms_skeleton is defined the transforms will be provided by bones.
	// If hlms_pose is not combined with hlms_skeleton the object's worldMat and worldView have to be set.
	@property( !hlms_skeleton )
		vec4 worldMat[3];
		worldMat[0] = bufferFetch( worldMatBuf, poseDataStart + 2 );
		worldMat[1] = bufferFetch( worldMatBuf, poseDataStart + 3 );
		worldMat[2] = bufferFetch( worldMatBuf, poseDataStart + 4 );
		vec4 worldPos;
		worldPos.x = dot( worldMat[0], inputPos );
		worldPos.y = dot( worldMat[1], inputPos );
		worldPos.z = dot( worldMat[2], inputPos );
		worldPos.w = 1.0;
		
		@property( hlms_normal || hlms_qtangent )
		@foreach( 4, n )
			vec4 row@n = bufferFetch( worldMatBuf, poseDataStart + 5 + @n ); @end
		mat4 worldView = mat4( row0, row1, row2, row3 );
		@end
	@end
@end @end // PoseTransform

@property( hlms_skeleton )
	@piece( worldViewMat )passBuf.view@end
@end @property( !hlms_skeleton )
    @piece( worldViewMat )worldView@end
@end

@piece( CalculatePsPos )(@insertpiece(local_vertex) * @insertpiece( worldViewMat )).xyz@end

@piece( VertexTransform )
@insertpiece( custom_vs_preTransform )
	//Lighting is in view space
	@property( hlms_normal || hlms_qtangent )outVs.pos		= @insertpiece( CalculatePsPos );@end
	@property( hlms_normal || hlms_qtangent )outVs.normal	= @insertpiece(local_normal) * mat3(@insertpiece( worldViewMat ));@end
	@property( normal_map )outVs.tangent	= @insertpiece(local_tangent) * mat3(@insertpiece( worldViewMat ));@end
@property( !hlms_dual_paraboloid_mapping )
	gl_Position = worldPos * passBuf.viewProj;@end
@property( hlms_dual_paraboloid_mapping )
	//Dual Paraboloid Mapping
	gl_Position.w	= 1.0f;
	@property( hlms_normal || hlms_qtangent )gl_Position.xyz	= outVs.pos;@end
	@property( !hlms_normal && !hlms_qtangent )gl_Position.xyz	= @insertpiece( CalculatePsPos );@end
	float L = length( gl_Position.xyz );
	gl_Position.z	+= 1.0f;
	gl_Position.xy	/= gl_Position.z;
	gl_Position.z	= (L - NearPlane) / (FarPlane - NearPlane);@end
@end

void main()
{
@property( !GL_ARB_base_instance )
    uint drawId = baseInstance + uint( gl_InstanceID );
@end

    @insertpiece( custom_vs_preExecution )

@property( !hlms_skeleton && !hlms_pose )

    mat3x4 worldMat = UNPACK_MAT3x4( worldMatBuf, drawId @property( !hlms_shadowcaster )<< 1u@end );
	@property( hlms_normal || hlms_qtangent )
	mat4 worldView = UNPACK_MAT4( worldMatBuf, (drawId << 1u) + 1u );
	@end

	vec4 worldPos = vec4( (vertex * worldMat).xyz, 1.0f );
@end

@property( hlms_qtangent )
	//Decode qTangent to TBN with reflection
	vec3 normal		= xAxis( normalize( qtangent ) );
	@property( normal_map )
	vec3 tangent	= yAxis( qtangent );
	outVs.biNormalReflection = sign( qtangent.w ); //We ensure in C++ qtangent.w is never 0
	@end
@end

	@insertpiece( PoseTransform )
	@insertpiece( SkeletonTransform )
	@insertpiece( VertexTransform )

	@insertpiece( DoShadowReceiveVS )
	@insertpiece( DoShadowCasterVS )

	/// hlms_uv_count will be 0 on shadow caster passes w/out alpha test
@foreach( hlms_uv_count, n )
	outVs.uv@n = uv@n;@end

@property( (!hlms_shadowcaster || alpha_test) && !lower_gpu_overhead )
	outVs.drawId = drawId;@end

	@property( hlms_use_prepass_msaa > 1 )
		outVs.zwDepth.xy = outVs.gl_Position.zw;
	@end

@property( hlms_global_clip_planes )
	gl_ClipDistance[0] = dot( float4( worldPos.xyz, 1.0 ), passBuf.clipPlane0.xyzw );
@end

	@insertpiece( custom_vs_posExecution )
}
