export interface ResponseMetadata {
  readonly requestId: string;
}

export interface SuccessResponse<T> {
  readonly data: T;
  readonly meta: ResponseMetadata;
}

export interface ErrorResponse {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly requestId: string;
    readonly fields?: Readonly<Record<string, readonly string[]>>;
    readonly details?: Readonly<Record<string, unknown>>;
  };
}

export function successResponse<T>(data: T, requestId: string): SuccessResponse<T> {
  return { data, meta: { requestId } };
}

export function errorResponse(
  code: string,
  message: string,
  requestId: string,
  options: {
    readonly fields?: Readonly<Record<string, readonly string[]>>;
    readonly details?: Readonly<Record<string, unknown>>;
  } = {},
): ErrorResponse {
  return {
    error: {
      code,
      message,
      requestId,
      ...(options.fields === undefined ? {} : { fields: options.fields }),
      ...(options.details === undefined ? {} : { details: options.details }),
    },
  };
}
