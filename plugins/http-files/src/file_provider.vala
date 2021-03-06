using Gee;
using Gtk;

using Dino.Entities;

namespace Dino.Plugins.HttpFiles {

public class FileProvider : Dino.FileProvider, Object {
    public string id { get { return "http"; } }

    private StreamInteractor stream_interactor;
    private Regex url_regex;
    private Regex file_ext_regex;

    private Gee.List<string> ignore_once = new ArrayList<string>();

    public FileProvider(StreamInteractor stream_interactor, Dino.Database dino_db) {
        this.stream_interactor = stream_interactor;
        this.url_regex = new Regex("""^(?i)\b((?:[a-z][\w-]+:(?:\/{1,3}|[a-z0-9%])|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))$""");
        this.file_ext_regex = new Regex("""\.(png|jpg|jpeg|svg|gif)""");

        stream_interactor.get_module(MessageProcessor.IDENTITY).message_received.connect(check_message);
        stream_interactor.get_module(MessageProcessor.IDENTITY).message_sent.connect(check_message);
        stream_interactor.get_module(Manager.IDENTITY).uploaded.connect((file_transfer, url) => {
            file_transfer.info = url;
            ignore_once.add(url);
        });
    }

    public void check_message(Message message, Conversation conversation) {
        if (ignore_once.remove(message.body)) return;
        Jid relevant_jid = stream_interactor.get_module(MucManager.IDENTITY).get_real_jid(message.from, conversation.account) ?? conversation.counterpart;
        bool in_roster = stream_interactor.get_module(RosterManager.IDENTITY).get_roster_item(conversation.account, relevant_jid) != null;
        if (message.direction == Message.DIRECTION_RECEIVED && !in_roster) return;
        if (message.body.length < 5) return;
        if (!url_regex.match(message.body)) return;
        if (!file_ext_regex.match(message.body)) return;

        var session = new Soup.Session();
        var head_message = new Soup.Message("HEAD", message.body);
        if (head_message != null) {
            session.send_message(head_message);
            string? content_type = null, content_length = null;
            print(message.body + ":\n");
            head_message.response_headers.foreach((name, val) => {
                print(name + " " + val + "\n");
                if (name == "Content-Type") content_type = val;
                if (name == "Content-Length") content_length = val;
            });
            if (/*content_type != null && content_type.has_prefix("image") &&*/ content_length != null && int.parse(content_length) < 5000000) {
                FileTransfer file_transfer = new FileTransfer();
                try {
                    Soup.Request request = session.request(message.body);
                    file_transfer.input_stream = request.send();
                } catch (Error e) {
                    return;
                }
                file_transfer.account = conversation.account;
                file_transfer.counterpart = message.counterpart;
                file_transfer.ourpart = message.ourpart;
                file_transfer.encryption = Encryption.NONE;
                file_transfer.time = message.time;
                file_transfer.local_time = message.local_time;
                file_transfer.direction = message.direction;
                file_transfer.file_name = message.body.substring(message.body.last_index_of("/") + 1);
                file_transfer.mime_type = content_type;
                file_transfer.size = int.parse(content_length);
                file_transfer.state = FileTransfer.State.NOT_STARTED;
                file_transfer.provider = 0;
                file_transfer.info = message.body;
                file_incoming(file_transfer);
            }
        }
    }
}

}
