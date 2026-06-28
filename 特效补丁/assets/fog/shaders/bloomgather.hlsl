//PRECOMPILE ps_all BloomGather
//PRECOMPILE ps_all BloomGather DST_FP32 1

#ifdef DST_FP32
	#pragma PSSL_target_output_format (target 0 FMT_32_GR)
#endif

CBUFFER_BEGIN(cdepth_aware_blur) 
	int viewport_width;
	int viewport_height;
	int mips_count;
	float weight_mult;
	float4 frame_to_dynamic_scale;
	TEXTURE2D_DECL_UNIFORM_BINDLESS( src_sampler );
CBUFFER_END

TEXTURE2D_DECL_TEXTURE_BINDLESS( src_sampler );

struct PInput
{
	float4 screen_coord : SV_POSITION;
	float2 tex_coord : TEXCOORD0;
};

float4 BloomGather( PInput input ) : PIXEL_RETURN_SEMANTIC
{
	float2 pixel_tex_size = 1.0f / float2(viewport_width, viewport_height);
	float2 tex_coord = input.screen_coord.xy * pixel_tex_size;

	/*float4 sum_data = 0.0f;
	float sum_weight = 1e-5f;

	int2 radii_int = int2(radii.xy + 0.5);

	int2 dir = radii_int.x > radii_int.y ? int2(1, 0) : int2(0, 1);
	int radius = max(radii_int.x, radii_int.y); 
	[loop]
	for(int offset = -radius; offset < radius; offset++)
	{
		int2 offset2 = dir * offset;
		float2 offset_tex_coord = tex_coord + pixel_tex_size * offset2;
		float4 data_sample = SAMPLE_TEX2DLOD(data_sampler, SamplerPointClamp, float4(offset_tex_coord, 0.0f, mip_level));

		sum_data += pow(data_sample, gamma);
		sum_weight += 1.0f;
	}

	return pow(sum_data / sum_weight, 1.0f / gamma);*/
	float4 res = 0.0f;
	float total_weight = 0.0f;
	float weight = 1.0f;
	float intensities[10] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f};
	//float weight_mult = 1.5f;
	for(int mip_level = 1; mip_level < 6; mip_level++)
	{
		//weight = intensities[min(mip_level, 9)];//mip_level == 4 ? 1.0f : 0.0f;//1.0f / (1.0f + 2.0f * mip_level);;
		weight = pow(weight_mult, mip_level);
		res += SAMPLE_TEX2DLOD_BINDLESS(src_sampler, SamplerLinearClampNoBias, float4(tex_coord, 0.0f, mip_level)) * weight;
		total_weight += weight;
	}
	return res / (total_weight + 1e-7f);
}
