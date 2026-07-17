# Repository Guidelines

## Project Structure & Module Organization

Lore is a Dart workspace organized as a local-first Flutter monorepo.

- `apps/lore_app/`: macOS- and Android-targeted Flutter application, platform setup, providers, and feature UI.
- `packages/lore_domain/`: dependency-free domain models and rules.
- `packages/lore_application/`: use cases, services, and repository ports.
- `packages/lore_storage/`: local filesystem persistence and recovery logic.
- `packages/lore_editor/`: text editing and Markdown preview components.
- `packages/lore_ui/`: shared themes and reusable presentation styles.
- `docs/designs/` and `docs/decisions/`: product, architecture, and decision records.
- `contracts/`: reserved shared schemas and API contracts for a future backend.

Keep tests beside their package under `test/`, such as `packages/lore_storage/test/`.

## Architecture Overview

Dependencies should flow inward: UI and storage depend on application ports and domain types, while the domain package remains independent. Add future server code as a separate workspace area rather than coupling backend concerns into Flutter packages.

## Build, Test, and Development Commands

Run commands from the repository root unless shown otherwise:

```bash
flutter pub get                         # Resolve workspace dependencies
dart format .                          # Format all Dart source
flutter analyze                        # Run workspace lint and type checks
(cd packages/lore_application && dart test)
(cd packages/lore_storage && flutter test)
(cd apps/lore_app && flutter test)
(cd apps/lore_app && flutter run -d macos)
```

Use `flutter run -d android` from `apps/lore_app/` when validating Android behavior.

## Coding Style & Naming Conventions

Use two-space indentation and rely on `dart format`; do not hand-align code. Follow `flutter_lints` from the root `analysis_options.yaml`. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and `snake_case.dart` for files. Prefer immutable models, explicit domain types, and small widgets or services with a single responsibility.

## Testing Guidelines

Use `package:test` for pure Dart packages and `flutter_test` for Flutter-dependent code. Name tests by observable behavior, for example `preserves chapter ids after external rename`. Add regression coverage for storage recovery, path safety, controller state, and responsive UI changes. Run the narrowest relevant test first, then `flutter analyze` and affected package suites.

## Commit & Pull Request Guidelines

History follows Conventional Commits, for example `feat: add writing workspace` and `chore: initialize Lore monorepo`. Keep commits focused and use prefixes such as `feat:`, `fix:`, `docs:`, `test:`, or `chore:`. Pull requests should explain user-visible behavior, list validation commands, link relevant issues or design documents, and include screenshots for UI changes. Call out migrations, metadata format changes, and known platform limitations explicitly.
