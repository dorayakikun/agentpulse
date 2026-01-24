import { useTasks } from "./hooks/useTasks";
import { Header } from "./components/Header";
import { TaskList } from "./components/TaskList";
import { EmptyState } from "./components/EmptyState";
import "./styles/variables.css";
import "./App.css";

function App() {
  const { tasks, isLoading, error, dismissTask } = useTasks();

  return (
    <div className="app">
      <Header taskCount={tasks.length} />
      <main className="main">
        {isLoading ? (
          <div className="loading">
            <div className="loading-spinner" />
            <span>Loading...</span>
          </div>
        ) : error ? (
          <div className="error">
            <p>{error}</p>
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
