(function() {
  requirejs.config({
    paths: {
      'backbone': '/vendor/backbone/backbone',
      'jquery': '/vendor/jquery/dist/jquery',
      'underscore': '/vendor/underscore/underscore',
      'json': '/vendor/requirejs-plugins/src/json',
      'text': '/vendor/requirejs-text/text',
      'requirejs': '/vendor/requirejs/require'
    }
  });

  define(['backbone', 'json'], function() {
    var $data, $filename, $form, $upload, showBlock;
    $upload = $('#upload');
    $data = $('#data');
    $filename = $('#data-filename');
    $form = $('section.main form');
    showBlock = function(block) {
      $('section.main form').toggleClass('hidden', block !== 'form');
      $('div.loading').toggleClass('hidden', block !== 'loading');
      $('div.fail').toggleClass('hidden', block !== 'fail');
      return $('div.done').toggleClass('hidden', block !== 'done');
    };
    $upload.on('click', function(e) {
      e.preventDefault();
      return $data.click();
    });
    return $data.on('change', function(e) {
      $filename.html(e.target.files[0].name);
      showBlock('loading');
      return $form.submit();
    });
  });

}).call(this);
