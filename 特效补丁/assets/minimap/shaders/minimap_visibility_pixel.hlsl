//PRECOMPILE ps_all RenderVisibility

CBUFFER_BEGIN( cminimap_visibility_pixel )
	float4 explored_tile;
	float4 tile_map_size;
	float4 visibility_map_size;
	float4 revealed_bound;
	float visibility_radius;


	float visibility_fully_revealed;
	float visibility_walkable_revealed;
	float visibility_reset;
	bool use_revealed_bound;
CBUFFER_END

TEXTURE2D_DECL( curr_visibility_sampler );
TEXTURE2D_DECL( walkability_sampler );

struct PS_INPUT
{
	float4 pixel_coord : SV_POSITION;
	float2 texture_uv : TEXCOORD0;
};

float RectDist( float4 rect, float2 p )
{
	float dist_x = max(max(rect.x - p.x, p.x - rect.z), 0);
	float dist_y = max(max(rect.y - p.y, p.y - rect.w), 0);
	return length(float2(dist_x, dist_y));
}

float4 RenderVisibility( const PS_INPUT input ) : PIXEL_RETURN_SEMANTIC
{
	float2 uv = input.pixel_coord.xy / visibility_map_size.xy;
	float2 planar_pos = uv * tile_map_size.xy;

	float dist = length(planar_pos - explored_tile.xy);
	
	if (use_revealed_bound)
		dist = min(dist, RectDist(revealed_bound, planar_pos));
		
	float ratio = saturate((1.0f - dist / visibility_radius) * 2.0f);

	float2 viewport_size = visibility_map_size.xy;

	float2 normalized_pos = input.pixel_coord.xy / viewport_size.xy;

	float prev_ratio = SAMPLE_TEX2D( curr_visibility_sampler, SamplerLinearClamp, normalized_pos ).r;

	float4 res_color = float4(max(ratio, prev_ratio), 0.0f, 0.0f, 1.0f);
	if(visibility_reset > 0.5f)
		
 {
 res_color = float4(0.18f, 0.0f, 0.0f, 1.0f);
 return res_color;
 }
 
	if(visibility_fully_revealed > 0.5f)
		res_color = float4(1.0f, 0.0f, 0.0f, 1.0f);
	if(visibility_walkable_revealed > 0.5f)
	{
		float4 walkability_sample = SAMPLE_TEX2D(walkability_sampler, SamplerLinearClamp, uv);
		float res_ratio = (1.0f - saturate(walkability_sample.r));
		//this reveals only walkable area inside a revealed_bound rectangle when it's specified
		if(abs(revealed_bound.x - revealed_bound.z) + abs(revealed_bound.y - revealed_bound.w) > 1e-2f)
		{
			res_ratio = max(prev_ratio, min(res_ratio, ratio));
		}
		res_color = float4(max(prev_ratio, res_ratio), 0.0f, 0.0f, 1.0f);
	}
	
 res_color.r = max(res_color.r, 0.1f);
 return res_color;
}