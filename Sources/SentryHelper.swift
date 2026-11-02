import Foundation

// The Sentry SDK was removed from this fork. These helpers keep their call
// sites compiling and do nothing.

/// Formerly added a Sentry breadcrumb; now a no-op.
func sentryBreadcrumb(_ message: String, category: String = "ui", data: [String: Any]? = nil) {}

/// Formerly captured a Sentry warning; now a no-op.
func sentryCaptureWarning(
    _ message: String,
    category: String = "ui",
    data: [String: Any]? = nil,
    contextKey: String? = nil
) {}

/// Formerly captured a Sentry error; now a no-op.
func sentryCaptureError(
    _ message: String,
    category: String = "ui",
    data: [String: Any]? = nil,
    contextKey: String? = nil
) {}

@MainActor
func sentryStartMemoryContextRefresh() {}

@MainActor
func sentryStopMemoryContextRefresh() {}
