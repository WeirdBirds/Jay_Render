Mesh_Component :: struct {
    // !ACHTUNG! Do not change handles directly. Use set_mesh, set_material, etc. to keep track of used/unused assets.
    _mesh: Handle;
    _material_slots: u32;
    _materials: [MAX_MATERIAL_SLOTS]Handle;
    _render_groups: [MAX_MATERIAL_SLOTS]u32;
    _mehs_instances: [MAX_MATERIAL_SLOTS]u32;
}

// set_mesh :: (component: *Mesh_Component, mesh_name: Name) -> bool { 
//     return set_mesh(component, retain(Mesh_Data, mesh_name));
// }
//
// set_mesh :: (component: *Mesh_Component, mesh_handle: Handle) -> bool #modify {return Handle.type == Mesh_Data;} {
//     release(component._mesh);
//     component._mesh = mesh_handle;
//
//     if component._render_instance  {
//
//     }
// }


Render_System_Group :: struct {
    #import "Jay_ECS";

    on_model_create :: (entity: Entity, event: Component_Event(Mesh_Component)) {
        log("new mesh: %", event.new_value.*);
    } @run_on:created(Mesh_Component)
    
    on_model_change :: (entity: Entity, event: Component_Event(Mesh_Component)) {
        log("mesh changed: % -> %", event.last_value.*, event.new_value.*);
    } @run_on:changed(Mesh_Component)
    
    on_model_delete :: (entity: Entity, event: Component_Event(Mesh_Component)) {
        log("mesh deleted: %", event.last_value.*);
    } @run_on:destroyed(Mesh_Component)
}
