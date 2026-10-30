import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/purchase_repository.dart';

sealed class PurchaseEvent extends Equatable {
  const PurchaseEvent();
  @override
  List<Object?> get props => [];
}

final class PurchaseRequested extends PurchaseEvent {
  const PurchaseRequested(this.productId, this.quantity);
  final int productId, quantity;
  @override
  List<Object?> get props => [productId, quantity];
}

final class PurchaseCleared extends PurchaseEvent {
  const PurchaseCleared();
}

enum PurchaseStatus { idle, processing, success, failure }

class PurchaseState extends Equatable {
  const PurchaseState({this.status = PurchaseStatus.idle, this.message});
  final PurchaseStatus status;
  final String? message;
  @override
  List<Object?> get props => [status, message];
}

class PurchaseBloc extends Bloc<PurchaseEvent, PurchaseState> {
  PurchaseBloc(this._repository) : super(const PurchaseState()) {
    on<PurchaseRequested>((event, emit) async {
      emit(const PurchaseState(status: PurchaseStatus.processing));
      try {
        final result = await _repository.buy(event.productId, event.quantity);
        emit(PurchaseState(
            status: PurchaseStatus.success,
            message: 'Order ${result.orderId} confirmed'));
      } catch (error) {
        emit(PurchaseState(
            status: PurchaseStatus.failure, message: error.toString()));
      }
    });
    on<PurchaseCleared>((event, emit) => emit(const PurchaseState()));
  }
  final PurchaseRepository _repository;
}
