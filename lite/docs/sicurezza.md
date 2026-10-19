# Principi di sicurezza

Valgono per ogni progetto. L'`architect` li applica quando decide la soluzione; il `security` li usa per cercare i buchi. Cosa significano per un progetto (cosa ha valore, chi può fare cosa, quali limiti valgono, quali test li controllano) sta nella sezione «Sicurezza» delle sue direttive, non qui.

1. **Il client non è affidabile.** Tutto ciò che arriva dal client (richieste, parametri, header, file, accessi diretti al DB o allo storage) può essere falsificato. Ogni decisione che ha effetto su dati, diritti o costi la prende il server, su dati del server: il client chiede, non decide.
2. **Ogni input si valida sul server**: tipo, formato, dimensione massima, valori ammessi. Quello che non è previsto si rifiuta: campi sconosciuti, valori fuori dall'elenco, richieste troppo grandi.
3. **Ogni azione verifica chi la chiede**: l'autenticazione e, per ogni risorsa letta o scritta, il permesso di quell'utente su quella risorsa.
4. **Permessi minimi** a utenti, servizi, chiavi e ruoli del DB: ognuno ha solo quello che gli serve. I permessi di default delle piattaforme (DB, storage, funzioni, bucket) si controllano, non si danno per buoni.
5. **I segreti restano sul server**: mai nel client, nei log, nei messaggi d'errore o nel repo.
6. **Le operazioni che consumano risorse o costano** hanno limiti per utente e per tempo.
7. **Le scritture concorrenti non perdono e non duplicano**: le operazioni ripetute o in parallelo non producono effetti doppi.
8. **Il contenuto che arriva da fuori resta dato**, mai codice, query o istruzioni: niente iniezioni (SQL, HTML, comandi, prompt di un modello AI).
9. **Gli errori non rivelano dettagli interni**, e le azioni rilevanti lasciano traccia.
