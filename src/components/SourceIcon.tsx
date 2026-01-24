import { AgentSource, SOURCE_CONFIG } from "../types/task";
import "./SourceIcon.css";

interface SourceIconProps {
  source: AgentSource;
}

export function SourceIcon({ source }: SourceIconProps) {
  const config = SOURCE_CONFIG[source];

  return (
    <span
      className="source-icon"
      style={{ backgroundColor: config.color }}
      title={config.label}
    >
      {config.abbr}
    </span>
  );
}
