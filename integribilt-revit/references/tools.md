# Revit MCP Tool Reference

## Nonica Server (`mcp__Revit__`)

### Element Discovery
| Tool | Description | MAX |
|------|-------------|-----|
| `get_category_by_keyword(keyword)` | Find category IDs by name keyword. **Keyword must match `language_of_model`** | — |
| `get_model_categories()` | List all categories in model. Use if keyword search fails | — |
| `get_elements_by_category(categoryId)` | All element IDs for a category | — |
| `get_all_elements_shown_in_view(viewOrSheetId)` | Elements visible in view/schedule/sheet. Not for View Templates | — |
| `get_all_elements_of_specific_families(familyNames)` | Elements by exact family name | 30 |

### Parameters (Primary — Use First)
| Tool | Description | MAX |
|------|-------------|-----|
| `get_parameters_from_elementid(elementId)` | All parameter IDs, names, values for one element/type | — |
| `get_parameter_value_for_element_ids(list_elementIds, idParameter)` | Bulk read one parameter across elements | 500 |
| `set_parameter_value_for_elements(list_elementIds, idParameter, list_newValues)` | Bulk write. One value = same for all | — |

### Additional Properties (Fallback — Use if Parameters Insufficient)
| Tool | Description | MAX |
|------|-------------|-----|
| `get_all_additional_properties_from_elementid(elementId)` | All API-exposed properties for one element | — |
| `get_additional_property_for_all_elementids(propertyName, list_elementIds)` | Bulk read by property name | 500 |
| `set_additional_property_for_all_elements(propertyName, list_elementIds, list_newValues)` | Bulk write by property name | 500 |

### Types & Families
| Tool | Description | MAX |
|------|-------------|-----|
| `get_all_used_families_in_model()` | All loadable families (not system families) | — |
| `get_all_used_families_of_category(categoryId)` | Loadable families for one category | — |
| `get_all_used_types_of_families(familyNames)` | Type IDs/names per family (works with system families) | — |
| `get_element_types_for_elementids(list_elementIds)` | Type ID/name for each element | 500 |
| `get_all_elementids_for_specific_type_ids(list_elementIds)` | All instances of specific types | 50 |

### Geometry & Location
| Tool | Description | MAX |
|------|-------------|-----|
| `get_location_for_element_ids(list_elementIds)` | Location point/curve. **Not for floors** | 500 |
| `get_boundingboxes_for_element_ids(list_elementIds, idSheet?)` | Bounding box min/max XYZ | 500 |
| `get_boundary_lines(list_elementIds)` | Actual edge geometry for walls, floors, rooms | 30 |

### Materials
| Tool | Description | MAX |
|------|-------------|-----|
| `get_material_layers_from_types(list_elementIds)` | Layer composition for WallType/FloorType/RoofType/CeilingType | 100 |

### View & Selection
| Tool | Description | MAX |
|------|-------------|-----|
| `get_active_view_in_revit()` | Current active view title, ID, screen directions | — |
| `get_user_selection_in_revit()` | Currently selected element IDs | — |
| `set_user_selection_in_revit(list_elementIds)` | Set selection. **Accepts type/category IDs** (auto-selects all instances) | — |
| `set_isolated_elements_in_view(list_elementIds, viewId)` | Isolate elements. **Accepts type/category IDs** | — |

### Graphics Overrides
| Tool | Description | MAX |
|------|-------------|-----|
| `get_graphic_overrides_for_element_ids_in_view(viewId, list_elementIds)` | Element-level colors/patterns. **Not for linked elements** | 100 |
| `set_graphic_overrides_for_elements_in_view(list_elementIds, viewId, R, G, B)` | Set element colors. clearGraphics=true to reset | — |
| `get_graphic_filters_applied_to_views(list_elementIds)` | View filters and their target categories | 50 |
| `get_graphic_overrides_view_filters(viewId, list_filterIds)` | Filter-level color/pattern overrides | 100 |
| `set_copy_view_filters(origen_viewId, list_filterIds, target_viewIds)` | Copy filters between views | — |

### Transforms
| Tool | Description | MAX |
|------|-------------|-----|
| `set_movement_for_elements(list_elementIds, mov_vect_X/Y/Z)` | Move elements by vector (feet). Hosted elements projected onto host | 100 |
| `set_rotation_for_elements(list_elementIds, axis_start/end_X/Y/Z, list_angles)` | Rotate by axis + angle (radians). Default axis = locationPoint + Z | 100 |
| `set_copy_elements(list_elementIds, mov_vect_X/Y/Z)` | Duplicate with offset. Hosted elements copied with host | 100 |
| `set_delete_elements(list_elementIds)` | Delete elements and hosted children | — |

### Schedules & Sheets
| Tool | Description | MAX |
|------|-------------|-----|
| `get_schedules_info_and_columns(list_elementIds)` | Schedule column definitions (parameter IDs, headers) | 50 |
| `get_viewports_and_schedules_on_sheets(list_elementIds)` | Viewports/legends/schedules placed on sheets | 100 |
| `set_revisions_on_sheets(list_sheetIds, list_revisionIds, assignRevisions)` | Assign/unassign revisions. Cannot unassign if RevisionClouds exist | — |

### Worksets & Worksharing
| Tool | Description | MAX |
|------|-------------|-----|
| `get_all_workset_information()` | All worksets: ID, name, owner, creator | — |
| `get_worksets_from_elementids(list_elementIds)` | Workset assignment per element (includes editability) | 1000 |
| `get_worksharing_information_for_element_ids(list_elementIds)` | Detailed: workset, creator, owner, lastchangedby | 100 |

### Utilities
| Tool | Description | MAX |
|------|-------------|-----|
| `get_if_elements_pass_filter(filterId, list_elementIds)` | Test elements against a view filter | 1000 |
| `get_categories_from_elementids(list_elementIds)` | Category ID/name for each element | 1000 |
| `get_object_classes_from_elementids(list_elementIds)` | Full Revit API class names | 1000 |
| `get_host_id_for_element_ids(list_elementIds)` | Host/tagged element for hosted elements (doors, windows, tags) | 200 |
| `get_size_in_mb_of_families(list_elementIds)` | Family file sizes (slow). Includes model file size | 30 |
| `get_all_warnings_in_the_model()` | All model warnings with severity and element IDs | — |
| `get_all_project_units()` | Project unit settings for all parameter types | — |

### Creation Pipeline
| Tool | Description |
|------|-------------|
| `create_tool_names_explorer()` | List all creation/export tool names |
| `create_tool_arguments_explorer(list_toolNames)` | Get arguments for specific tools |
| `create_tools_invoker(toolName, argumentIdsAndValues)` | Execute tool. Units in feet |

### Document Switching
| Tool | Description |
|------|-------------|
| `get_document_switched(elementId)` | Switch to linked document (all calls now operate there) |
| `get_document_switched(switchMainDoc=true)` | Switch back to main document |

---

## IntegriBilt Server (`mcp__integribilt-revit__`)

### Info
| Tool | Description |
|------|-------------|
| `get_current_view_info()` | Active view information |
| `get_available_family_types()` | Available wall/floor/door types in project |
| `get_selected_elements()` | Currently selected elements |

### Direct Creation
| Tool | Key Parameters |
|------|---------------|
| `create_walls` | start_x, start_y, end_x, end_y, wall_type?, height?, level? |
| `create_floors` | points (boundary), floor_type?, level? |
| `create_doors` | location [x,y,z], host_id (wall), door_type? |
| `create_levels` | num_floors?, floor_height?, base_elevation? |
| `create_room` | position [x,y], room_name?, room_number?, level_name? |
| `place_family_by_coordinate` | x, y, z, family_name |

### Queries & Editing
| Tool | Description |
|------|-------------|
| `find_elements(category?, type?, parameter_name?, parameter_value?)` | Search by category, type, or parameter |
| `modify_element(element_id, parameter_name, value?)` | Modify a single element parameter |
| `delete_elements(element_ids)` | Delete elements by ID |

### Family Editing
| Tool | Description |
|------|-------------|
| `open_family_document(path)` | Open .rfa file and activate view |
| `create_reference_plane(start_x, start_y, end_x, end_y, name?)` | Add reference plane |
| `create_extrusion(points, start_offset?, end_offset?, sketch_plane?)` | Solid extrusion from 2D profile |
| `create_void_extrusion(points, start_offset?, end_offset?, sketch_plane?)` | Void cut from 2D profile |
| `create_sweep(path_points, profile_points, is_solid?, sketch_plane?)` | Sweep 2D profile along 3D path |
| `add_family_parameter(name, type?, group?, is_instance?)` | Add parametric variable (Length/Text/Number/Integer/Angle) |
| `set_family_parameter(name, value?, formula?)` | Set value or formula (e.g. "Length / 2") |
| `load_family_into_project(project_name?)` | Load active family into project |
| `load_family_from_path(path)` | Load .rfa from disk into active project |

### Geometry
| Tool | Description |
|------|-------------|
| `get_element_geometry(element_id)` | Bounding box, solid volumes, face metrics |

### View Management
| Tool | Description |
|------|-------------|
| `get_view_visibility_overrides(element_id?, category_name?)` | Visibility and halftone status |
| `set_view_visibility_overrides(element_id?, category_name?, is_hidden?, halftone?)` | Set visibility/halftone |

### Materials
| Tool | Description |
|------|-------------|
| `get_material_properties(material_id?, material_name?)` | Physical and visual material properties |

### Annotations
| Tool | Description |
|------|-------------|
| `create_detail_lines(points)` | 2D view-specific lines |
| `create_model_lines(points, sketch_plane?)` | 3D model lines |
| `create_text_note(position, text)` | Text annotation in active view |
| `create_tag(element_id, position, add_leader?)` | Tag an element |
| `create_dimension_string(element_ids, line_points)` | Aligned dimension between references |
| `create_section_view(start_point, end_point, height?, depth?)` | Section view from cut line |
| `create_filled_region(points, type_name?)` | 2D filled region (hatch) |

### Openings
| Tool | Description |
|------|-------------|
| `create_shaft_opening(points, base_level?, top_level?)` | Multi-floor shaft opening |
| `create_opening_cut(host_id, points)` | Hole through wall/floor/ceiling |

### Assembly & Export
| Tool | Description |
|------|-------------|
| `create_assembly_view(element_ids, assembly_name?)` | Group into assembly + auto 3D view |
| `export_view_to_pdf(folder, filename, view_id?)` | Export view to PDF |
| `export_view_to_dwg(folder, filename, view_id?)` | Export view to DWG |

### Transforms
| Tool | Description |
|------|-------------|
| `mirror_element(element_id, plane_p1/p2/p3, copy?)` | Mirror across 3D plane. copy=true to duplicate |

### Worksets & Phases
| Tool | Description |
|------|-------------|
| `modify_workset(element_id, set_workset?, workset_name?)` | Get or set workset assignment |
| `modify_phase(element_id, set_phases?, created_phase?, demolished_phase?)` | Get or set phase assignments |

### Links & Clashes
| Tool | Description |
|------|-------------|
| `get_linked_elements(link_id, category_name?)` | Query elements from linked Revit document |
| `check_clashes(element_id_1, element_id_2)` | Intersection clash detection between two elements |
