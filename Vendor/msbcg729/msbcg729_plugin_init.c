#include "mediastreamer2/msfilter.h"

extern MSFilterDesc ms_bcg729_dec_desc;
extern MSFilterDesc ms_bcg729_enc_desc;

__attribute__((visibility("default"))) void libmsbcg729_init(MSFactory *factory) {
	ms_factory_register_filter(factory, &ms_bcg729_dec_desc);
	ms_factory_register_filter(factory, &ms_bcg729_enc_desc);
	ms_message("libmsbcg729 plugin loaded (bcg729, G.729 Annex A/B)");
}
