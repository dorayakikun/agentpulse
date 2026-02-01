// Error response from backend
export interface AppError {
  code: string;
  message: string;
}

// Error code definitions
export const ErrorCodes = {
  SOCKET_ERROR: 'SOCKET_ERROR',
  JSON_PARSE_ERROR: 'JSON_PARSE_ERROR',
  TASK_NOT_FOUND: 'TASK_NOT_FOUND',
  INVALID_EVENT: 'INVALID_EVENT',
  NOTIFICATION_ERROR: 'NOTIFICATION_ERROR',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];

// User-facing messages
export const ErrorMessages: Record<ErrorCode, string> = {
  SOCKET_ERROR: 'Connection error. The monitoring service may be unavailable.',
  JSON_PARSE_ERROR: 'Failed to process data from agent.',
  TASK_NOT_FOUND: 'Task not found. It may have already completed.',
  INVALID_EVENT: 'Received invalid data from agent.',
  NOTIFICATION_ERROR: 'Failed to send notification.',
  INTERNAL_ERROR: 'An unexpected error occurred.',
};

// Get user-facing message from error
export function getUserMessage(error: AppError | Error | unknown): string {
  if (error && typeof error === 'object' && 'code' in error) {
    const appError = error as AppError;
    return ErrorMessages[appError.code as ErrorCode] || appError.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return 'An unexpected error occurred.';
}
