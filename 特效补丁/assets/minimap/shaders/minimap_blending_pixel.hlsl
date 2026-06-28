//PRECOMPILE ps_all BlendMinimap

CBUFFER_BEGIN( cminimap_blending_pixel )
	float4 viewport_size;
	float geometry_opacity;
	float walkability_opacity;
	float sdr_scale;
	bool use_royale_data;
CBUFFER_END

TEXTURE2D_DECL( walkability_sampler );
TEXTURE2D_DECL( geometry_sampler );

#include "Shaders/Include/OETF.hlsl"

struct PS_INPUT
{
	float4 screen_coord : SV_POSITION;
	float2 texture_uv : TEXCOORD0;
};

float4 Uberblend(float4 col0, float4 col1)
{
	return float4(
		lerp(
			lerp((col0.rgb * col0.a + col1.rgb * col1.a) / (col0.a + col1.a + 1e-2f), (col1.rgb), col1.a),
			lerp((col0.rgb * (1.0 - col1.a) + col1.rgb * col1.a), (col1.rgb), col1.a),
			col0.a),
		min(1.0, 1.0f - (1.0f - col0.a) * (1.0f - col1.a)));
}

float3 Vibrance(float val, float3 color)
{
	return pow(saturate(3.0f * val * val - 2.0f * val * val * val), 1.0f / (color + 1e-6));
}

float SmoothStep(float val, float center, float curve)
{
	float eps = 1e-7f;
	val = min(val, 1.0f - eps);
	val = max(val , eps);
	float power = 2.0f / max(1e-3f, 1.0f - curve) - 1.0f;
	return 1.0f - center + 
	(
		-pow(saturate(1.0f - max(center, val)), power) * pow(saturate(1.0f - center), -(power - 1.0f)) +
		 pow(saturate(       min(center, val)), power) * pow(saturate(       center), -(power - 1.0f))
	);
}

float4 BlendMinimap( const PS_INPUT input ) : PIXEL_RETURN_SEMANTIC
{
	float2 screen_coord = input.screen_coord.xy / viewport_size.xy;

	float4 walkability_sample = SAMPLE_TEX2D( walkability_sampler, SamplerLinearClampOffsetNoBias, screen_coord );


	float walkable_dist = walkability_sample.r;

	float eps = 4.5e-1f;
	float aa_width = 2e-1f;

	float walkable_to_edge_ratio = saturate((walkable_dist - (eps - aa_width)) / aa_width);
	float edge_to_unwalkable_ratio = saturate((walkable_dist - (1.0f - eps)) / aa_width);

	//res_color = lerp(float4(1.0f, 1.0f, 1.0f, 0.01f), float4(1.0f, 1.0f, 1.0f, 0.3f), walkable_to_edge_ratio);
	
 float4 walkable_color = float4(0.0f, 0.0f, 0.0f, 0.3f);
 
	float4 walkability_map_color = lerp(walkable_color, float4(1.00f, 0.85f, 0.10f, 0.85f), walkable_to_edge_ratio);
	walkability_map_color = lerp(walkability_map_color, float4(walkability_map_color.rgb, 0.0f), edge_to_unwalkable_ratio);
	float visibility = saturate(walkability_sample.g * 2.0f);

	float unexplored_edge = saturate(visibility * (1.0f - visibility) * 4.0f * saturate(2.0f - 2.0f * walkable_dist));

	float4 geometry_sample = SAMPLE_TEX2D( geometry_sampler, SamplerLinearClampOffsetNoBias, screen_coord );
	float color_key_fade = saturate(length(geometry_sample.rgb - float3(0.0f, 0.0f, 0.0f)) * 50.0f);
	geometry_sample.a *= color_key_fade;

	walkability_map_color = lerp(walkability_map_color, float4(0.0f, 0.5f, 1.0f, 0.5f), pow(saturate(unexplored_edge), 25.0f));

	float max_walkable_fade = lerp(1.0f, 0.3f, walkability_opacity);
	geometry_sample.a = lerp(geometry_sample.a, geometry_sample.a * max_walkable_fade, (1.0f - edge_to_unwalkable_ratio));
	geometry_sample.a *= geometry_opacity;
	walkability_map_color.a *= walkability_opacity;

	float4 res_color = walkability_map_color;
	res_color = Uberblend(res_color, geometry_sample * float4(1.0f, 1.0f, 1.0f, visibility));

	// Synthesis stuff
	if( !use_royale_data )
	{	
		res_color.a *= saturate(1.0f - walkability_sample.b * 2.0f);
		res_color.rgb *= res_color.a;

		//float3 color = pow(float3(132, 181, 255) / 255.0f, 2.2f);
		//float3 color = pow(float3(255, 115, 79) / 255.0f, 2.2f);
		float3 color = pow(float3(244, 161, 66) / 255.0f, 2.2f);

		float decay_glow = walkability_sample.a - 1.0f + (	walkability_sample.b) * 2.0f;
		//float decay_glow = SmoothStep(walkability_sample.b, 1.0f - walkability_sample.a, 0.4f) * 1.1f;
		//float decay_glow = walkability_sample.b;
		
		decay_glow = (decay_glow > 0.99f) ? 0.0f : pow(saturate(decay_glow), 2.0f) * 0.8f;
		//float4 decay_edge_color = float4(Vibrance(decay_edge * 0.6f, color, 0.5f), 1.0f - pow(saturate(1.0f - decay_edge), 2.0f));
		float decay_edge = saturate((1.0f - pow(abs(walkability_sample.b - 0.5f) * 4.0f, 3.0f))) * visibility;
		float4 decay_edge_color = float4(Vibrance(decay_glow, color), 1.0f - pow(saturate(1.0f - decay_edge), 2.0f));
		decay_edge_color.rgb *= visibility;
		res_color.rgb += decay_edge_color.rgb;
	}
	else
	{
		res_color.rgb *= res_color.a;

		// Royale
		if( walkability_sample.a > 0.0f )
			res_color = lerp( res_color, float4(15.0f/255.0f, 159.0f/255.0f, 255.0f/255.0f, 1.0f), saturate( walkability_sample.a ) / 2.0f * visibility );
		else if( walkability_sample.b > 0.0f )
			res_color = lerp( res_color, float4(255.0f/255.0f, 35.0f/255.0f, 0.0f/255.0f, 1.0f), saturate( walkability_sample.b ) / 2.0f * visibility );
	}

	
 float map_content_mask = saturate(geometry_sample.a * 20.0f + walkability_sample.r * 5.0f);
 res_color.a *= map_content_mask;
 
 return OutputSDR(res_color,sdr_scale);
	//return Uberblend(walkability_map_color, geometry_sample) * float4(1.0f, 1.0f, 1.0f, visibility);
}