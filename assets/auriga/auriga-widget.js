(function () {
    window.AurigaWidget = {
        boot: function (config) {
            const container = document.getElementById("auriga-container");
            if (container) {
                container.innerHTML = `
            <div style="padding:20px; background:#fff; border:1px solid #ddd; border-radius:10px;">
              <h3>Auriga Widget</h3>
              <p>OrgId: ${config.orgId}</p>
            </div>
          `;
            }
        },
    };
})();
  