import { FC } from 'react';

interface ErrorBannerProps {
  message: string;
  onDismiss?: () => void;
  onRetry?: () => void;
}

export const ErrorBanner: FC<ErrorBannerProps> = ({
  message,
  onDismiss,
  onRetry,
}) => {
  return (
    <div className="error-banner" role="alert">
      <div className="error-banner-content">
        <span className="error-icon">!</span>
        <p className="error-message">{message}</p>
      </div>
      <div className="error-banner-actions">
        {onRetry && (
          <button className="error-action" onClick={onRetry}>
            Retry
          </button>
        )}
        {onDismiss && (
          <button
            className="error-dismiss"
            onClick={onDismiss}
            aria-label="Dismiss"
          >
            &times;
          </button>
        )}
      </div>
    </div>
  );
};
