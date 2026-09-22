import json
from tools.structural_visual_contract import load_dimensions, validate_geometry

def box(lo, hi):
    p=[(lo[0],lo[1],lo[2]),(hi[0],lo[1],lo[2]),(hi[0],hi[1],lo[2]),(lo[0],hi[1],lo[2]),
       (lo[0],lo[1],hi[2]),(hi[0],lo[1],hi[2]),(hi[0],hi[1],hi[2]),(lo[0],hi[1],hi[2])]
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]
    return [[p[a],p[b],p[c]] for q in faces for a,b,c in [(q[0],q[1],q[2]),(q[0],q[2],q[3])]]

policy=load_dimensions()
# End faces are set back 10 cm, with a thin cap preserving the full AABB.
wall_gap=box((-1.9,0,-.1),(1.9,3.1,.1))+box((-2,3.1,-.1),(2,3.2,.1))
# Thin flat boundary skirts plus a recessed interior: different from a full slab.
floor_skirt=box((-2,-.25,-2),(2,-.24,2))+box((-1.99,-.24,-1.99),(1.99,0,1.99))
print(json.dumps({
'valid_floor':validate_geometry('floor_1x1',box((-2,-.25,-2),(2,0,2)),policy),
'wall_recessed_terminal_face':validate_geometry('wall_straight_1x1',wall_gap,policy),
'floor_skirt_gap':validate_geometry('floor_1x1',floor_skirt,policy),
},indent=2))
