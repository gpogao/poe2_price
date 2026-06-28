//PRECOMPILE ps_all BloomCutoff
//PRECOMPILE ps_all BloomCutoff DST_FP32 1

#ifdef DST_FP32
	#pragma PSSL_target_output_format (target 0 FMT_32_GR)
#endif

CBUFFER_BEGIN(cdepth_aware_blur) 
	int viewport_width;
	int viewport_height;
	float cutoff;
	float intensity;
	float4 frame_to_dynamic_scale;
	TEXTURE2D_DECL_UNIFORM_BINDLESS( src_sampler );
CBUFFER_END

TEXTURE2D_DECL_TEXTURE_BINDLESS( src_sampler );

struct PInput
{
	float4 screen_coord : SV_POSITION;
	float2 tex_coord : TEXCOORD0;
};


float3 Luminance(float3 color)
{
	return dot(color, float3(1.0f, 1.0f, 1.0f)) / 3.0f;
}
float4 BloomCutoff( PInput input ) : PIXEL_RETURN_SEMANTIC
{
	float2 pixel_tex_size = 1.0f / float2(viewport_width, viewport_height);
	float2 tex_coord = input.screen_coord.xy * pixel_tex_size * frame_to_dynamic_scale.xy;
	
	float4 color_sample = SAMPLE_TEX2DLOD_BINDLESS(src_sampler, SamplerPointClampNoBias, float4(tex_coord, 0.0f, 0.0f));
	float luminance = Luminance(color_sample.rgb).r;
	float mult = max(0.0f, luminance - cutoff) * intensity;
	return float4(color_sample.rgb * mult, color_sample.a);
}
