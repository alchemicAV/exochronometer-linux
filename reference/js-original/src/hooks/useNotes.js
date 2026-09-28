import { useState, useCallback } from 'react';

const STORAGE_KEY = 'exochronometer_notes';

const loadNotes = () => {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch {
    return [];
  }
};

export function useNotes() {
  const [notes, setNotes] = useState(loadNotes);

  const addNote = useCallback((text, currentDegrees) => {
    const note = {
      id: crypto.randomUUID(),
      timestamp: Date.now(),
      text,
      degrees: { ...currentDegrees },
    };
    setNotes((prev) => {
      const updated = [...prev, note];
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
      return updated;
    });
  }, []);

  const deleteNote = useCallback((id) => {
    setNotes((prev) => {
      const updated = prev.filter((n) => n.id !== id);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
      return updated;
    });
  }, []);

  return { notes, addNote, deleteNote };
}
