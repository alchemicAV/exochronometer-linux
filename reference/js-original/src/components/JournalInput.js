import React, { useState } from 'react';
import './JournalInput.css';

const JournalInput = ({ onAddNote }) => {
  const [text, setText] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed) return;
    onAddNote(trimmed);
    setText('');
  };

  return (
    <form className="journal-input" onSubmit={handleSubmit}>
      <div className="journal-input__row">
        <input
          type="text"
          className="journal-input__field"
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Add a note at the current moment...notes are stored locally"
          spellCheck={false}
        />
        <button type="submit" className="journal-input__btn" disabled={!text.trim()}>
          LOG
        </button>
      </div>
    </form>
  );
};

export default JournalInput;
