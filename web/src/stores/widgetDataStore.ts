import { create } from 'zustand';

import type { BankTx } from '@/apps/banking/bankingApi';
import type { Vehicle } from '@/apps/garages/data';
import type { Company } from '@/apps/services/data';
import type { Inbox } from '@/apps/services/servicesApi';
import type { Asset } from '@/apps/stocks/data';
import type { Article } from '@/apps/weazelnews/data';
import type { RydeSync } from '@/apps/ryde/rydeApi';
import type { HealthPayload, WeatherPayload } from '@/core/types';

const num = (v: unknown): number | null =>
    (typeof v === 'number' && Number.isFinite(v) ? v : null);

interface WidgetDataState {
    weather: WeatherPayload | null;
    balance: number | null;
    cash: number | null;
    transactions: BankTx[];
    health: HealthPayload | null;
    vehicles: Vehicle[];
    assets: Asset[];
    articles: Article[];
    ticker: string[];
    businesses: Company[];
    businessInbox: Inbox | null;
    businessHere: { x: number; y: number } | null;
    businessUnavailable: string | null;
    ryde: RydeSync | null;
    setWeather: (w: WeatherPayload | null) => void;
    setWallet: (balance: number | null, cash: number | null, transactions: BankTx[]) => void;
    setHealth: (h: HealthPayload | null) => void;
    setVehicles: (v: Vehicle[]) => void;
    setAssets: (a: Asset[]) => void;
    setPrices: (ticks: PriceTick[]) => void;
    setNews: (articles: Article[], ticker: string[]) => void;
    setBusinesses: (companies: Company[], inbox: Inbox | null, here: { x: number; y: number } | null, unavailable?: string | null) => void;
    setRyde: (sync: RydeSync | null) => void;
}

interface PriceTick { symbol: string; price: number; changePct: number }

const HISTORY_CAP = 60;

export const useWidgetData = create<WidgetDataState>((set) => ({
    weather: null,
    balance: null,
    cash: null,
    transactions: [],
    health: null,
    vehicles: [],
    assets: [],
    articles: [],
    ticker: [],
    businesses: [],
    businessInbox: null,
    businessHere: null,
    businessUnavailable: null,
    ryde: null,
    setWeather: (weather) => set({ weather }),
    setWallet: (balance, cash, transactions) => set({
        balance: num(balance),
        cash: num(cash),
        transactions: Array.isArray(transactions) ? transactions.slice(0, 16) : [],
    }),
    setHealth: (health) => set({ health }),
    setVehicles: (vehicles) => set({ vehicles: Array.isArray(vehicles) ? vehicles.slice(0, 12) : [] }),
    setAssets: (assets) => set({ assets: Array.isArray(assets) ? assets : [] }),
    setPrices: (ticks) => set(s => {
        if (!Array.isArray(ticks) || ticks.length === 0 || s.assets.length === 0) return {};
        const by = new Map(ticks.map(t => [t.symbol, t]));
        return {
            assets: s.assets.map(a => {
                const t = by.get(a.symbol);
                if (!t || typeof t.price !== 'number') return a;
                const history = [...a.history, t.price];
                if (history.length > HISTORY_CAP) history.shift();
                return { ...a, price: t.price, changePct: t.changePct, history };
            }),
        };
    }),
    setNews: (articles, ticker) => set({
        articles: Array.isArray(articles) ? articles.slice(0, 6) : [],
        ticker: Array.isArray(ticker) ? ticker.slice(0, 8) : [],
    }),
    setBusinesses: (businesses, businessInbox, businessHere, businessUnavailable = null) => set({
        businesses: Array.isArray(businesses) ? businesses : [],
        businessInbox,
        businessHere,
        businessUnavailable,
    }),
    setRyde: (ryde) => set({ ryde }),
}));
