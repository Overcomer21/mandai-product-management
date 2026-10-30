# VGV-inspired Flutter architecture

Feature-first structure using `flutter_bloc` with typed **Events**, immutable **States**, repositories and reusable widgets.

- `app/`: dependency composition, theme, shell.
- `core/network/`: injectable HTTP client and API error handling.
- `core/widgets/`: reusable stateless visual components.
- `features/auth/`: `AuthBloc`, events, states, authentication repository, login view.
- `features/products/`: `ProductBloc`, events, states, product repository, CRUD editor and catalog.
- `features/purchases/`: `PurchaseBloc`, events, states, purchasing repository.

UI dispatches events. Blocs handle async workflow and expose state. Repositories perform HTTP calls and parse typed DTOs. Flutter never accesses SQL Server directly. Backend alone owns inventory transaction and RBAC rules. `BuildContext` is not passed via child constructors.

`_QuantityDialog` uses widget-local state only for quantity selection; application state is managed by Bloc. Do not claim this is an exact official VGV template; it is an architecture inspired by its engineering style.

## Validation

Run `flutter pub get`, `dart format lib test`, `flutter analyze`, `flutter test` using a locally installed Flutter SDK. Backend regression tests and SQL Server integration tests must also pass. The Flutter SDK is not installed in the artifact-generation environment, so Flutter compilation has not been independently verified here.
