# Panda CCD iOS audio compatibility

Base: vol_spotter_ios 0.2.1, MIT; original LICENSE retained.
VolumeButtonDetector keeps an existing `.record`/`.playAndRecord` category.
Starting the volume shutter must not replace the camera's Live audio session
with `.ambient`. Other plugin behavior, including KVO volume observation and
its limitations at route changes, is unchanged and requires iPhone testing.
