export class AppError extends Error {
  override readonly name = 'AppError';

  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
    readonly fields?: Readonly<Record<string, readonly string[]>>,
    options?: ErrorOptions,
  ) {
    super(message, options);
  }
}
