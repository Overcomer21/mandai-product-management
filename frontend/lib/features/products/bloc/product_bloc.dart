import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/product.dart';
import '../data/product_repository.dart';

sealed class ProductEvent extends Equatable {
  const ProductEvent();
  @override
  List<Object?> get props => [];
}

final class ProductsRequested extends ProductEvent {
  const ProductsRequested(this.admin);
  final bool admin;
  @override
  List<Object?> get props => [admin];
}

final class ProductSaved extends ProductEvent {
  const ProductSaved(this.input, {this.id});
  final ProductInput input;
  final int? id;
  @override
  List<Object?> get props => [input, id];
}

final class ProductDeactivated extends ProductEvent {
  const ProductDeactivated(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

enum ProductStatus { initial, loading, ready, failure }

class ProductState extends Equatable {
  const ProductState(
      {this.status = ProductStatus.initial,
      this.products = const [],
      this.error,
      this.admin = false,
      this.notice});
  final ProductStatus status;
  final List<Product> products;
  final String? error, notice;
  final bool admin;
  @override
  List<Object?> get props => [status, products, error, admin, notice];
}

class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._repository) : super(const ProductState()) {
    on<ProductsRequested>((event, emit) async => _load(event.admin, emit));
    on<ProductSaved>((event, emit) async {
      try {
        await _repository.save(event.input, id: event.id);
        await _load(state.admin, emit, notice: 'Product saved');
      } catch (error) {
        emit(ProductState(
            status: ProductStatus.failure,
            products: state.products,
            admin: state.admin,
            error: error.toString()));
      }
    });
    on<ProductDeactivated>((event, emit) async {
      try {
        await _repository.deactivate(event.id);
        await _load(state.admin, emit, notice: 'Product deactivated');
      } catch (error) {
        emit(ProductState(
            status: ProductStatus.failure,
            products: state.products,
            admin: state.admin,
            error: error.toString()));
      }
    });
  }
  final ProductRepository _repository;
  Future<void> _load(bool admin, Emitter<ProductState> emit,
      {String? notice}) async {
    emit(ProductState(
        status: ProductStatus.loading, products: state.products, admin: admin));
    try {
      emit(ProductState(
          status: ProductStatus.ready,
          products: await _repository.list(admin: admin),
          admin: admin,
          notice: notice));
    } catch (error) {
      emit(ProductState(
          status: ProductStatus.failure,
          products: state.products,
          admin: admin,
          error: error.toString()));
    }
  }
}
