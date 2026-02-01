import "./Header.css";

interface HeaderProps {
  taskCount: number;
}

export function Header({ taskCount }: HeaderProps) {
  return (
    <header className="header">
      <h1 className="header-title">AgentPulse</h1>
      <span className="header-count">
        {taskCount} {taskCount === 1 ? "task" : "tasks"}
      </span>
    </header>
  );
}
