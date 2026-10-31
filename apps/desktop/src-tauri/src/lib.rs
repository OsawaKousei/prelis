use tauri::Manager;

fn initial_window_size(
    inner: tauri::PhysicalSize<u32>,
    outer: tauri::PhysicalSize<u32>,
    available: tauri::PhysicalSize<u32>,
    scale_factor: f64,
) -> tauri::PhysicalSize<u32> {
    let minimum = tauri::LogicalSize::new(800.0, 600.0).to_physical::<u32>(scale_factor);
    tauri::PhysicalSize::new(
        inner.width.min(
            available
                .width
                .saturating_sub(outer.width.saturating_sub(inner.width))
                .max(minimum.width),
        ),
        inner.height.min(
            available
                .height
                .saturating_sub(outer.height.saturating_sub(inner.height))
                .max(minimum.height),
        ),
    )
}

fn fit_initial_window(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    if window.is_fullscreen()? || window.is_maximized()? {
        return Ok(());
    }
    if let Some(monitor) = window.current_monitor()? {
        let inner = window.inner_size()?;
        let outer = window.outer_size()?;
        let area = monitor.work_area();
        let size = initial_window_size(inner, outer, area.size, window.scale_factor()?);
        if size != inner {
            window.set_size(size)?;
            let width = size.width + outer.width.saturating_sub(inner.width);
            let height = size.height + outer.height.saturating_sub(inner.height);
            window.set_position(tauri::PhysicalPosition::new(
                area.position.x + (area.size.width.saturating_sub(width) / 2) as i32,
                area.position.y + (area.size.height.saturating_sub(height) / 2) as i32,
            ))?;
        }
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/128x128.png"))?;
            if let Some(window) = app.get_webview_window("main") {
                window.set_icon(icon)?;
                if let Err(error) = fit_initial_window(&window) {
                    eprintln!("Could not fit the initial window to the monitor: {error}");
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::initial_window_size;
    use tauri::PhysicalSize;

    #[test]
    fn fits_laptop_work_area_including_window_decorations() {
        assert_eq!(
            initial_window_size(
                PhysicalSize::new(1280, 860),
                PhysicalSize::new(1296, 899),
                PhysicalSize::new(1366, 728),
                1.0,
            ),
            PhysicalSize::new(1280, 689),
        );
    }

    #[test]
    fn preserves_default_size_when_it_fits() {
        assert_eq!(
            initial_window_size(
                PhysicalSize::new(1280, 860),
                PhysicalSize::new(1296, 899),
                PhysicalSize::new(1920, 1040),
                1.0,
            ),
            PhysicalSize::new(1280, 860),
        );
    }

    #[test]
    fn respects_logical_minimum_on_scaled_displays() {
        assert_eq!(
            initial_window_size(
                PhysicalSize::new(1920, 1290),
                PhysicalSize::new(1944, 1349),
                PhysicalSize::new(1366, 900),
                1.5,
            ),
            PhysicalSize::new(1342, 900),
        );
    }
}
