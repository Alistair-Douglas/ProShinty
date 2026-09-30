// Tree canopy blob (see ShintyPitch._canopy_mesh): a lumpy core plus leaf
// cards cut out with a procedural leaf pattern. Leaf colour comes from the
// MultiMesh instance colour. Normals point out from the blob centre so each
// blob shades as one soft mass; the whole crown sways a little in the wind.
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

#include "res://pitch/canopy.gdshaderinc"
