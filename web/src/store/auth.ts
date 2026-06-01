import { create } from 'zustand';
import { api } from '@/api/client';
import { getStatus } from '@/api/status';

// Default server URL is sourced from web/.env (VITE_DEFAULT_SERVER_URL) so it
// no longer needs to be entered in the login UI.
const DEFAULT_SERVER_URL = (import.meta.env.VITE_DEFAULT_SERVER_URL as string) || '';

interface AuthState {
  token: string;
  serverUrl: string;
  isAuthenticated: boolean;
  checking: boolean;
  login: (token: string, serverUrl?: string) => void;
  logout: () => void;
  init: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set) => ({
  token: '',
  serverUrl: DEFAULT_SERVER_URL,
  isAuthenticated: false,
  checking: true,
  login: (token: string, serverUrl?: string) => {
    api.setToken(token);
    localStorage.setItem('cc_token', token);
    const url = serverUrl || DEFAULT_SERVER_URL;
    if (url) localStorage.setItem('cc_server_url', url);
    set({ token, serverUrl: url, isAuthenticated: true, checking: false });
  },
  logout: () => {
    api.setToken('');
    localStorage.removeItem('cc_token');
    localStorage.removeItem('cc_server_url');
    set({ token: '', serverUrl: DEFAULT_SERVER_URL, isAuthenticated: false, checking: false });
  },
  init: async () => {
    const token = localStorage.getItem('cc_token') || '';
    const serverUrl = localStorage.getItem('cc_server_url') || DEFAULT_SERVER_URL;
    if (token) {
      api.setToken(token);
      set({ token, serverUrl, isAuthenticated: true, checking: false });
      return;
    }
    // No stored token: probe whether the server requires auth at all.
    // If /status succeeds without a token, the server has no token configured,
    // so we skip the login screen entirely.
    try {
      api.setToken('');
      await getStatus();
      set({ serverUrl, isAuthenticated: true, checking: false });
    } catch {
      set({ serverUrl, isAuthenticated: false, checking: false });
    }
  },
}));
