import { addListener, initMockBridge } from "./mockState";

initMockBridge();

export type UnlistenFn = () => void;

export const listen = async <T>(
  eventName: string,
  handler: (event: { payload: T }) => void
): Promise<UnlistenFn> => {
  return addListener(eventName, handler);
};
