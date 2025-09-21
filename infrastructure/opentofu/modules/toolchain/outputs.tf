output "manifest_path" {
  description = "Absolute path to the generated toolchain manifest"
  value       = local_file.toolchain_manifest.filename
}
