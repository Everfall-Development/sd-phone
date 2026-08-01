import { createContext, useContext } from 'react';

const MdtRootContext = createContext<HTMLElement | null>(null);

export const MdtRootProvider = MdtRootContext.Provider;

export function useMdtRoot(): HTMLElement | null {
    return useContext(MdtRootContext);
}
