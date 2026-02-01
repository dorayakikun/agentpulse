import { useTasks } from './hooks/useTasks';
import { Header } from './components/Header';
import { TaskList } from './components/TaskList';
import { EmptyState } from './components/EmptyState';
import { ErrorBanner } from './components/ErrorBanner';
import './styles/variables.css';
import './App.css';

function App() {
  const { tasks, isLoading, error, refresh, dismissTask, clearError } =
    useTasks();

  return (
    <div className="app">
      <Header taskCount={tasks.length} />
      {error && (
        <ErrorBanner
          message={error}
          onRetry={() => {
            clearError();
            void refresh();
          }}
          onDismiss={clearError}
        />
      )}
      <main className="main">
        {isLoading ? (
          <div className="loading">
            <div className="loading-spinner" />
            <span>Loading...</span>
          </div>
        ) : tasks.length === 0 ? (
          <EmptyState />
        ) : (
          <TaskList tasks={tasks} onDismiss={dismissTask} />
        )}
      </main>
    </div>
  );
}

export default App;
