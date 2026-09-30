// Far trees: the canopy blob without leaf cards, drawn opaque (cheap to draw
// and to cast shadows with). See canopy.gdshaderinc.
shader_type spatial;
render_mode diffuse_burley;

#define FAR
#include "res://pitch/canopy.gdshaderinc"
