import { useState } from "react";
import { greet } from "@prelis/core";
import "./App.css";

function App() {
  const [name, setName] = useState("Prelis");

  return (
    <main className="container">
      <h1>Prelis</h1>
      <label htmlFor="greet-input">Name</label>
      <div className="row">
        <input
          id="greet-input"
          value={name}
          onChange={(event) => setName(event.currentTarget.value)}
          placeholder="Enter a name..."
        />
      </div>
      <p aria-live="polite">{greet(name)}</p>
    </main>
  );
}

export default App;
