$(function () {
  $('#msg').focus();

  var log = function (text) {
    $('#log').val( $('#log').val() + text + "\n");
  };

  var ws = new WebSocket($('#url').data('url'));
  ws.onopen = function () {
    log('Connection opened');
  };

  ws.onmessage = function (msg) {
    log(msg.data);
  };

$('#msg').keydown(function (e) {
    if (e.keyCode == 13 && $('#msg').val()) {
        ws.send($('#msg').val());
        $('#msg').val('');
    }
  });
});
