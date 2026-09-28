import React from 'react';
import './NotePanel.css';

const NotePanel = ({ notes, nodeDegree, onClose, onDelete, position }) => {
  const style = {
    left: position.x,
    top: position.y,
    transform: 'translate(-50%, 8px)',
  };

  return (
    <div className="note-panel-overlay" onClick={onClose}>
      <div
        className="note-panel"
        style={style}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="note-panel-header">
          Notes at {Math.round(nodeDegree)}°
        </div>
        {notes.length === 0 ? (
          <div className="note-empty">No notes</div>
        ) : (
          notes.map((note) => (
            <div key={note.id} className="note-item">
              <button className="note-delete" onClick={() => onDelete(note.id)}>
                ×
              </button>
              <div className="note-text">{note.text}</div>
              <div className="note-meta">
                {new Date(note.timestamp).toLocaleString()}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};

export default NotePanel;
